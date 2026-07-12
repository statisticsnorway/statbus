#!/bin/bash
# StatBus installer
#
# This is the ONE command for both fresh installs and rescue/upgrade:
#   curl -fsSL https://statbus.org/install.sh | bash                         # stable channel (default)
#   curl -fsSL https://statbus.org/install.sh | bash -s -- --channel prerelease
#   curl -fsSL https://statbus.org/install.sh | bash -s -- --channel edge
#   curl -fsSL https://statbus.org/install.sh | bash -s -- --version vX.Y.Z
#
# It always runs from the user's home directory (via curl | bash).
# It always targets ~/statbus/ as the installation directory.
#
# Two modes, detected automatically:
#   Fresh:   ~/statbus/.git doesn't exist → git clone, download binary, ./sb install
#   Rescue:  ~/statbus/.git exists        → replace binary, ./sb install --version
#
# Separation of concerns:
#   install.sh   → gets the RIGHT binary and RIGHT source code into ~/statbus/
#   ./sb install → handles EVERYTHING else (config, docker, DB, service)
#
# The directory ~/statbus/ is ALWAYS created by git clone — never mkdir.
# The binary /sb is in .gitignore — placing it doesn't dirty the working tree.
#
# Concurrency safety (STATBUS-039): ./sb install's dispatcher handles a
# running upgrade service ITSELF — a genuinely-progressing upgrade (flag
# held, unit healthy) makes install REFUSE with a wait-and-retry message; a
# crash-looping unit (NRestarts >= 3) is taken over with a SIGKILL-class
# quiesce and the wedged upgrade is recovered. Callers must NOT stop the
# service first: `systemctl --user stop` sends SIGTERM, which an in-flight
# upgrade catches and answers with a rollback (snapshot restore over the
# live DB) — the deploy-stop footgun that wedged rune. The binary swap
# needs no stop either: this script places ./sb via curl-to-sb.tmp + mv
# (atomic rename), so a running service never causes "text file busy".
# Fresh installs have no service to conflict with.
#
set -euo pipefail

# Merge stderr → stdout so every error (git, curl, ./sb) reaches the
# operator regardless of how the script was invoked. The primary path is
# `curl | bash` over SSH, where standalone.sh / cloud.sh capture SSH's
# stdout+stderr via `2>&1` on the outer SSH call. Without this merge,
# there is a narrow window where SSH closes its stderr channel before the
# remote process fully flushes — swallowing e.g. "pathspec 'v…' did not
# match" from git checkout. Merging at the source eliminates that window.
exec 2>&1

# Print the failing command and line number before set -e exits so the
# operator sees exactly which step broke, even when the command itself is
# silent or its error went to stderr before the merge above took effect.
trap 'rc=$?; echo "" >&2; echo "install.sh FAILED at line $LINENO: $BASH_COMMAND (exit $rc)" >&2' ERR

# Parse arguments — install.sh-specific flags are consumed here;
# anything else is forwarded to ./sb install (e.g. --trust-github-user).
#
# --version vX.Y.Z   install the explicit tag
# --channel <name>   resolve version from channel. Valid names:
#                      stable     — latest non-prerelease via /releases/latest (default)
#                      prerelease — latest v*-rc.* via /releases API
#                      edge       — master HEAD, version string "sha-<short>"
# --commit <sha>     STATBUS-082: edge-with-a-pin. Check out the EXACT 40-hex commit
#                    and procure its PUBLISHED statbus-sb image (NO build fallback —
#                    determinism). Mutually exclusive with --version/--channel.
#                    Harness + developer audience; operators use stable/prerelease.
# No flag            equivalent to --channel stable.
# --prerelease       REMOVED. Prints a rename notice and exits 1. Callers must
#                    switch to --channel prerelease (cloud.sh + standalone.sh
#                    already do so post-rc.62).
VERSION=""
CHANNEL=""
COMMIT_SHA=""
SB_INSTALL_ARGS=""
while [ $# -gt 0 ]; do
    case "$1" in
        --version) VERSION="$2"; shift 2 ;;
        --channel) CHANNEL="$2"; shift 2 ;;
        --commit) COMMIT_SHA="$2"; shift 2 ;;
        --prerelease)
            echo "Error: --prerelease was renamed. Use --channel prerelease instead." >&2
            exit 1
            ;;
        --trust-github-user) SB_INSTALL_ARGS="$SB_INSTALL_ARGS --trust-github-user $2"; shift 2 ;;
        *) echo "Unknown option: $1"; exit 1 ;;
    esac
done

# STATBUS-082: --commit <full-40-hex-sha> is edge-with-a-pin — mutually exclusive
# with --version and --channel (any combination refuses), full lowercase hex only
# (commit-is-authoritative doctrine: artifacts are named by full SHA). Its audience
# is the harness + developers; NSO operators stay on stable/prerelease.
if [ -n "$COMMIT_SHA" ]; then
    if [ -n "$VERSION" ] || [ -n "$CHANNEL" ]; then
        echo "Error: --commit is mutually exclusive with --version and --channel — pass only one." >&2
        exit 1
    fi
    case "$COMMIT_SHA" in
        *[!a-f0-9]*)
            echo "Error: --commit '$COMMIT_SHA' is not a full commit SHA — expected ^[a-f0-9]{40}\$ (40 lowercase hex chars)." >&2
            exit 1
            ;;
    esac
    if [ "${#COMMIT_SHA}" -ne 40 ]; then
        echo "Error: --commit '$COMMIT_SHA' is not a full commit SHA — expected ^[a-f0-9]{40}\$ (40 lowercase hex chars)." >&2
        exit 1
    fi
fi

# Default channel when neither --version nor --channel nor --commit supplied.
if [ -z "$VERSION" ] && [ -z "$CHANNEL" ] && [ -z "$COMMIT_SHA" ]; then
    CHANNEL="stable"
fi

# Validate channel name up front so the error message lands before any
# network work.
if [ -n "$CHANNEL" ]; then
    case "$CHANNEL" in
        stable|prerelease|edge) ;;
        *)
            echo "Error: Unknown channel '$CHANNEL'. Valid: stable, prerelease, edge." >&2
            exit 1
            ;;
    esac
fi

echo "StatBus Installer"
echo "================="

# Prerequisites
for cmd in git docker curl; do
    if ! command -v "$cmd" >/dev/null 2>&1; then
        echo "Error: $cmd is required but not installed."
        exit 1
    fi
done

# Detect OS and architecture
OS=$(uname -s | tr '[:upper:]' '[:lower:]')
ARCH=$(uname -m)
case "$ARCH" in
    x86_64)  ARCH="amd64" ;;
    aarch64) ARCH="arm64" ;;
    arm64)   ARCH="arm64" ;;
    *)       echo "Unsupported architecture: $ARCH"; exit 1 ;;
esac

# procure_sb_from_commit_image <version_short8> <allow_build_fallback: yes|no>
#
# STATBUS-082: the shared binary-procurement step for the two commit-tagged
# channels (edge and --commit). Both check out a git commit, then procure ~/statbus/sb
# from the commit-tagged image ghcr.io/statisticsnorway/statbus-sb:<short8> via
# docker pull → create → cp — NO host Go/make toolchain (mirrors `./sb db seed
# fetch` and the in-binary procureSbFromImage). The ONLY difference between the two
# channels is this function's second argument:
#   - edge (yes): if the image is unpublished (an UNPUSHED local edge commit), build
#     it locally via cli/Dockerfile.sb (golang runs IN-container; still no host Go) —
#     the toolchain-free dev/rescue case.
#   - --commit (no): REFUSE if the image is unpublished. Determinism is the flag's
#     whole point — the harness must test the commit's PUBLISHED image (the artifact
#     CI ships and the arc's upgrade legs pull); a silent in-VM build would mask a
#     CI-images gap and test a DIFFERENT artifact. The refusal names the image ref
#     and both remedies.
procure_sb_from_commit_image() {
    version="$1"
    allow_build_fallback="$2"
    SB_IMAGE="ghcr.io/statisticsnorway/statbus-sb:${version}"
    echo "Procuring sb from image ${SB_IMAGE} (no toolchain)..."
    if ! docker pull "$SB_IMAGE" >/dev/null 2>&1; then
        if [ "$allow_build_fallback" = "yes" ]; then
            echo "  no published image for ${version} — building locally via cli/Dockerfile.sb (golang runs in-container; no host Go)..."
            docker build -f cli/Dockerfile.sb \
                --build-arg VERSION="$version" \
                --build-arg COMMIT="$(git rev-parse HEAD)" \
                -t "$SB_IMAGE" ./cli
        else
            echo "Error: no published statbus-sb image for commit ${version}: ${SB_IMAGE}" >&2
            echo "  --commit tests the commit's PUBLISHED image (the artifact CI ships and the upgrade legs pull); it will NOT build a different binary locally." >&2
            echo "  Remedies:" >&2
            echo "    - wait for the images.yaml workflow to publish the image for this commit, then retry; or" >&2
            echo "    - use --channel edge if you genuinely want master HEAD with an in-container build fallback." >&2
            exit 1
        fi
    fi
    if ! sb_cid=$(docker create "$SB_IMAGE"); then
        echo "Error: docker create $SB_IMAGE failed — no sb binary to extract." >&2
        exit 1
    fi
    docker cp "${sb_cid}:/sb" "${STATBUS_DIR}/sb"
    docker rm "$sb_cid" >/dev/null 2>&1 || true
    chmod +x "${STATBUS_DIR}/sb"
    echo "Binary: $(./sb --version)"
    echo ""
}

# Resolve version from --version or --channel.
#
# All non-edge paths end with $VERSION set to a v-tag that has a published
# release binary at
#   https://github.com/statisticsnorway/statbus/releases/download/$VERSION/sb-$OS-$ARCH
# The edge path sets $VERSION to "sha-<short>" and builds from source
# (see edge block further down — it doesn't use $BINARY_URL).
STATBUS_DIR="${HOME}/statbus"
if [ -n "$VERSION" ]; then
    echo "Installing specified version: $VERSION"
elif [ "$CHANNEL" = "stable" ]; then
    echo "Checking for latest stable release..."
    VERSION=$(curl -sL https://api.github.com/repos/statisticsnorway/statbus/releases/latest 2>/dev/null \
        | grep '"tag_name"' | cut -d'"' -f4) || true
    if [ -z "$VERSION" ]; then
        echo "Error: No stable release published." >&2
        echo "Options:" >&2
        echo "  --channel prerelease     Install the latest pre-release (v*-rc.*)" >&2
        echo "  --channel edge           Install master HEAD (builds from source)" >&2
        echo "  --version v2026.03.0     Install a specific tag" >&2
        exit 1
    fi
    echo "Latest stable release: $VERSION"
elif [ "$CHANNEL" = "prerelease" ]; then
    echo "Checking for latest pre-release..."
    # Extract newest v*-rc.* tag via the /releases API. Sort numerically
    # by (year, month, patch, rc) to handle cross-month ordering without
    # relying on sort -V being available.
    VERSION=$(curl -sL "https://api.github.com/repos/statisticsnorway/statbus/releases?per_page=50" 2>/dev/null \
        | grep '"tag_name"' | cut -d'"' -f4 | grep '\-rc\.' \
        | awk -F'[v.\\-]' '{print $2*1e8 + $3*1e6 + $4*1e4 + $6+0, $0}' \
        | sort -n | tail -1 | awk '{print $2}') || true
    if [ -z "$VERSION" ]; then
        echo "Error: No pre-release published." >&2
        exit 1
    fi
    echo "Latest pre-release: $VERSION"
elif [ "$CHANNEL" = "edge" ]; then
    # Edge channel: clone master (no release tag to pin); VERSION becomes the
    # bare commit_short. STATBUS-061: the sb binary is PROCURED FROM THE
    # commit-tagged statbus-sb image (ghcr.io/statisticsnorway/statbus-sb:<short>,
    # built by images.yaml on every master push) via docker create + docker cp —
    # NO host Go/make toolchain (mirrors `./sb db seed fetch` and the in-binary
    # procureSbFromImage). If the commit has no published image (an UNPUSHED
    # local edge commit), build it locally via cli/Dockerfile.sb — golang runs
    # INSIDE the container, so still no host Go. This makes edge recovery
    # toolchain-free, closing the last gap in the legacy-recovery lever. Edge is
    # the dev-oriented path; production operators use stable or prerelease.
    if [ -d "$STATBUS_DIR/.git" ]; then
        echo "Updating existing installation (edge: master HEAD)..."
        cd "$STATBUS_DIR"
        # Fetch master into a real remote-tracking ref. A prior install via
        # stable/prerelease/--version cloned `--depth 1 --branch <tag>`
        # (single-branch, install.sh:256), so refs/remotes/origin/master does
        # NOT exist; a bare `git fetch origin master` updates only FETCH_HEAD and
        # the checkout below then dies "fatal: 'origin/master' is not a commit".
        # The explicit +src:dst refspec creates/updates the tracking ref directly,
        # mirroring git's default +refs/heads/*:refs/remotes/origin/* clone refspec.
        # Same single-branch-clone class as the db-seed fix at :237/:263.
        git fetch origin +master:refs/remotes/origin/master
        git checkout -B current origin/master
        # Item M (plan-rc.66): drop the legacy statbus/ namespace from
        # local-only state branches. Idempotent — swallows the "branch
        # not found" error on hosts that never had the legacy names.
        git branch -D statbus/current 2>/dev/null || true
        git branch -D statbus/pre-upgrade 2>/dev/null || true
    else
        echo "Cloning StatBus repository (edge: master)..."
        git clone --branch master \
            https://github.com/statisticsnorway/statbus.git "$STATBUS_DIR"
        cd "$STATBUS_DIR"
    fi
    # Rc.63: VERSION for edge is the bare commit_short (8-char). No
    # "sha-" prefix anywhere. The `./sb config generate` step below
    # re-computes COMMIT_SHORT from git, so .env is coherent even when
    # VERSION is set here and .env.config is generated later.
    VERSION="$(git rev-parse --short=8 HEAD)"
    echo "Edge version: $VERSION"
    # STATBUS-082: procurement factored into the shared function; edge allows the
    # in-container build fallback for an unpushed local commit.
    procure_sb_from_commit_image "$VERSION" "yes"
    # Edge path is fully resolved — skip the download-and-checkout
    # block below by jumping straight to the post-install steps.
    SKIP_BINARY_DOWNLOAD=1
elif [ -n "$COMMIT_SHA" ]; then
    # STATBUS-082: --commit is edge-with-a-pin — check out the EXACT sha (not the
    # moving master tip), procure sb from its PUBLISHED image with NO build fallback
    # (determinism: the harness must test the artifact CI ships). Downstream is
    # identical to edge; only the checkout target and the fallback policy differ.
    if [ -d "$STATBUS_DIR/.git" ]; then
        echo "Updating existing installation (commit: ${COMMIT_SHA})..."
        cd "$STATBUS_DIR"
    else
        echo "Cloning StatBus repository (commit: ${COMMIT_SHA})..."
        git clone https://github.com/statisticsnorway/statbus.git "$STATBUS_DIR"
        cd "$STATBUS_DIR"
    fi
    # Fetch the exact commit. An UNPUSHED local commit fails here naturally → the
    # refusal says 'push it first' (the harness's preflight_head_on_origin already
    # guarantees this for arc runs).
    if ! git fetch origin "$COMMIT_SHA"; then
        echo "Error: git fetch origin ${COMMIT_SHA} failed — is the commit pushed to origin?" >&2
        echo "  --commit checks out an exact origin commit; push it to origin first, then retry." >&2
        exit 1
    fi
    git checkout -B current "$COMMIT_SHA"
    # Drop the legacy statbus/ namespace from local-only state branches (mirrors edge).
    git branch -D statbus/current 2>/dev/null || true
    git branch -D statbus/pre-upgrade 2>/dev/null || true
    # VERSION = bare commit_short (8-char), the rc.63 convention shared with edge.
    VERSION="$(git rev-parse --short=8 HEAD)"
    echo "Commit version: $VERSION"
    procure_sb_from_commit_image "$VERSION" "no"
    # Fully resolved — skip the release download-and-checkout block below.
    SKIP_BINARY_DOWNLOAD=1
fi

BINARY_URL="https://github.com/statisticsnorway/statbus/releases/download/${VERSION}/sb-${OS}-${ARCH}"

if [ -z "${SKIP_BINARY_DOWNLOAD:-}" ]; then
    # Download binary to temp file (avoids conflict with running daemon)
    echo "Downloading StatBus $VERSION for ${OS}/${ARCH}..."
    curl -fsSL "$BINARY_URL" -o "${HOME}/sb.tmp"
    chmod +x "${HOME}/sb.tmp"

    if [ -d "$STATBUS_DIR/.git" ]; then
        # RESCUE: directory exists from previous install
        echo "Updating existing installation..."
        mv "${HOME}/sb.tmp" "${STATBUS_DIR}/sb"
        cd "$STATBUS_DIR"
        echo "Binary: $(./sb --version)"
        echo ""
        echo "Checking out $VERSION..."
        # Ensure db-seed is in origin's refspec so the subsequent
        # `./sb db seed fetch` (during `./sb install`) can populate the
        # origin/db-seed remote-tracking ref. Older rescue installs were
        # cloned via `--depth 1 --branch <tag>` which implies
        # --single-branch and restricts the refspec to JUST that branch —
        # `git fetch origin db-seed` then updates FETCH_HEAD but NOT
        # refs/remotes/origin/db-seed, and the later `git show
        # origin/db-seed:seed.pg_dump` fails with "invalid object name."
        # set-branches --add is idempotent; on hosts already broadened it
        # no-ops.
        git remote set-branches --add origin db-seed
        # No --force, no --quiet. install-verified moving tag was deleted
        # in rc.62; there is no moving tag to force past anymore. Silent
        # failures hid rune's rc.59 / rc.60 root causes — let fetch and
        # checkout print their own errors.
        git fetch origin --tags
        # Use a named local branch (`current`) so HEAD is never
        # detached on a tag. Parallels `pre-upgrade` — see
        # doc/upgrade-timeline.md#flag-file-mutex-install--service. -B resets the branch on each install,
        # so this is idempotent across re-runs.
        git checkout -B current "$VERSION"
        # Item M (plan-rc.66): drop the legacy statbus/ namespace from
        # local-only state branches. Idempotent — swallows the "branch
        # not found" error on hosts that never had the legacy names.
        git branch -D statbus/current 2>/dev/null || true
        git branch -D statbus/pre-upgrade 2>/dev/null || true
    else
        # FRESH: git clone creates the directory
        echo "Cloning StatBus repository..."
        git clone --depth 1 --branch "$VERSION" \
            https://github.com/statisticsnorway/statbus.git "$STATBUS_DIR"
        # Add db-seed to origin's refspec — see RESCUE-path comment above
        # for the bug this prevents. `--depth 1 --branch <tag>` implies
        # --single-branch which restricts the refspec; without this fix
        # the seed-restore step silently falls back to full-replay of all
        # migrations (1-3 min) instead of pg_restore (~2s).
        git -C "$STATBUS_DIR" remote set-branches --add origin db-seed
        # `clone --branch <tag>` leaves HEAD detached on the tag commit;
        # promote to the same `current` branch the rescue path uses.
        git -C "$STATBUS_DIR" checkout -B current "$VERSION"
        mv "${HOME}/sb.tmp" "${STATBUS_DIR}/sb"
        cd "$STATBUS_DIR"
        echo "Binary: $(./sb --version)"
        echo ""
    fi
fi

# Clear any stale terminal file from a prior failed run so the banner below
# only reflects invariants fired during THIS install, not ghosts from before.
rm -f "$STATBUS_DIR/tmp/install-terminal.txt" 2>/dev/null || true

# Run the Go-side installer. Do NOT `exec` — we need to handle non-zero
# exits and write a named-invariant banner + support bundle so operators
# have something actionable when they come back to "what happened".
set +e
./sb install $SB_INSTALL_ARGS
sb_rc=$?
set -e
# Sentinel: we reached here, so every bash-level step above succeeded.
# If the script died before this line (git checkout, curl, mv, etc.) the
# ERR trap fired and printed the failing command. If sb_rc != 0 the
# failure was inside the Go binary — not a bash-level exit.
echo "install.sh: ./sb install returned (exit $sb_rc)" >&2

if [ "$sb_rc" -eq 0 ]; then
    exit 0
fi

# Exit 75 (sysexits EX_TEMPFAIL): the upgrade attempt failed BUT rollback
# succeeded. System is back at the previous known-good version, services
# are up, maintenance is off. This is Category 2 of the recovery trifecta
# (rc.67) — distinct from a catastrophic ABORT. Print a banner that says
# so, and exit 0 (clean rollback IS a successful outcome of the failure
# path). The progress log printed above already carries the failure
# narrative; this banner just summarises it for an operator skimming the
# scrollback.
if [ "$sb_rc" -eq 75 ]; then
    echo ""
    echo "==============================================================================="
    echo "UPGRADE FAILED — system rolled back to previous version"
    echo "==============================================================================="
    echo ""
    echo "The upgrade attempt did not succeed, but rollback restored the prior"
    echo "version cleanly. Services are running; the maintenance banner is off."
    echo ""
    echo "To retry the upgrade after addressing the root cause: re-run this script."
    echo "==============================================================================="
    exit 0
fi

# Anything else is a catastrophic failure — gather a support bundle and
# write admin-UI state. Everything below is best-effort. If a step fails,
# continue to the next so the SYSTEM UNUSABLE banner always prints even
# when the DB is down or the bundle disk write fails.
echo ""
echo "==============================================================================="
echo "SYSTEM UNUSABLE — ./sb install failed (exit $sb_rc)"
echo "==============================================================================="

# 1. Named invariant that drove termination (empty when a panic or SIGKILL
#    aborted before a guard site could write install-terminal.txt).
terminal_file="$STATBUS_DIR/tmp/install-terminal.txt"
if [ -s "$terminal_file" ]; then
    invariant_line=$(tail -1 "$terminal_file")
    echo ""
    echo "Invariant breached:"
    echo "  $invariant_line"
else
    invariant_line="(no named invariant — ./sb install aborted before a guard site fired)"
    echo ""
    echo "Invariant breached: $invariant_line"
fi

# 2. Support bundle: writes ./support-bundle-<ts>.txt and prints the abs path.
bundle_path=""
if bundle_path=$(./sb support gather --trigger=install 2>/tmp/sb-support-gather.err); then
    echo ""
    echo "Support bundle: $bundle_path"
else
    echo ""
    echo "Support bundle: (gather failed — see /tmp/sb-support-gather.err)"
fi

# 3. Admin-UI state (best-effort — ./sb support write-admin-ui-row exits 0
#    when the DB is unreachable; we ignore the exit code either way).
./sb support write-admin-ui-row \
    --message "$invariant_line" \
    --bundle-path "${bundle_path:-}" \
    >/dev/null 2>&1 || true

# 4. Operator-facing instruction.
contact="${ADMINISTRATOR_CONTACT:-Contact your administrator}"
echo ""
echo "Next steps:"
echo "  $contact"
echo "  Attach the support bundle above to your support ticket."
echo "==============================================================================="

exit "$sb_rc"
