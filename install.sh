#!/bin/bash
# StatBus installer
#
# This is the ONE command for both fresh installs and rescue/upgrade:
#   curl -fsSL https://statbus.org/install.sh | bash -s -- --prerelease
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
# Concurrency safety: ./sb install's mutex check rejects the run if the upgrade
# service has written tmp/upgrade-in-progress.json. Callers who want to update
# a server that has a running service must stop it first (./cloud.sh install
# does this automatically; manual invocations should: systemctl --user stop
# statbus-upgrade@<slot>.service). Fresh installs have no service to conflict
# with.
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
trap 'rc=$?; echo ""; echo "install.sh: failed at line $LINENO: $BASH_COMMAND (exit $rc)"' ERR

# Parse arguments — install.sh-specific flags are consumed here;
# anything else is forwarded to ./sb install (e.g. --trust-github-user).
VERSION=""
PRERELEASE=false
SB_INSTALL_ARGS=""
while [ $# -gt 0 ]; do
    case "$1" in
        --version) VERSION="$2"; shift 2 ;;
        --prerelease) PRERELEASE=true; shift ;;
        --trust-github-user) SB_INSTALL_ARGS="$SB_INSTALL_ARGS --trust-github-user $2"; shift 2 ;;
        *) echo "Unknown option: $1"; exit 1 ;;
    esac
done

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

# Resolve version
if [ -n "$VERSION" ]; then
    echo "Installing specified version: $VERSION"
elif [ "$PRERELEASE" = true ]; then
    echo "Checking for latest verified pre-release..."

    # Pick the latest release tag whose commit IS install-verified or
    # an ANCESTOR of install-verified.
    #
    # `install-verified` is a moving git tag advanced by
    # .github/workflows/install-verified.yaml to the latest master
    # commit that passed BOTH ci-images.yaml AND install-test.yaml.
    # Releases at install-verified's commit (or earlier) have been
    # validated; releases at NEWER commits (descendants of
    # install-verified) have NOT — their CI may still be running, or
    # may have failed. Picking the latest verified-or-older release
    # avoids the bootstrap trap of installing a freshly-tagged RC
    # whose CI hasn't finished.
    #
    # We need ancestor information, which `git ls-remote` cannot
    # provide. Use a bare blob-less local clone — fast (~MB-scale,
    # seconds) since we don't pull file content, only commit/tree
    # metadata. The clone is ephemeral; trap removes it on exit.
    TMP_REF_REPO=$(mktemp -d -t statbus-resolver-XXXXXX)
    trap 'rm -rf "$TMP_REF_REPO"' EXIT
    if git clone --bare --filter=blob:none --quiet \
            https://github.com/statisticsnorway/statbus.git "$TMP_REF_REPO" >/dev/null 2>&1; then
        V_SHA=$(git -C "$TMP_REF_REPO" rev-parse install-verified 2>/dev/null) || V_SHA=""
        if [ -n "$V_SHA" ]; then
            # Walk RC tags newest-first by tag name. `--sort=-version:refname`
            # works on standard CalVer/SemVer-shaped tags.
            for TAG in $(git -C "$TMP_REF_REPO" tag -l 'v*' --sort=-version:refname); do
                case "$TAG" in
                    *-rc.*) ;;
                    *) continue ;;
                esac
                R_SHA=$(git -C "$TMP_REF_REPO" rev-parse "$TAG^{commit}" 2>/dev/null) || continue
                if git -C "$TMP_REF_REPO" merge-base --is-ancestor "$R_SHA" "$V_SHA" 2>/dev/null; then
                    VERSION="$TAG"
                    break
                fi
            done
        fi
    fi

    if [ -n "$VERSION" ]; then
        echo "Latest verified pre-release: $VERSION (commit $(git -C "$TMP_REF_REPO" rev-parse --short "$VERSION^{commit}") is install-verified or an ancestor; passed ci-images + install-test)"
    else
        echo "Note: install-verified ref unavailable or no RC ancestor of it — falling back to newest -rc."
        # Fallback: fetch releases, extract RC tags, sort by CalVer +
        # RC number numerically (sort -V isn't always available), pick
        # the highest. UNVERIFIED — operator should know.
        VERSION=$(curl -sL "https://api.github.com/repos/statisticsnorway/statbus/releases?per_page=50" 2>/dev/null \
            | grep '"tag_name"' | cut -d'"' -f4 | grep '\-rc\.' \
            | awk -F'[v.\\-]' '{print $2*1e8 + $3*1e6 + $4*1e4 + $6+0, $0}' \
            | sort -n | tail -1 | awk '{print $2}') || true
        if [ -z "$VERSION" ]; then
            echo "Error: No pre-release found."
            exit 1
        fi
        echo "Latest pre-release (UNVERIFIED — install-verified ref unavailable or no ancestor RC): $VERSION"
    fi
else
    echo "Checking for latest stable release..."
    VERSION=$(curl -sL https://api.github.com/repos/statisticsnorway/statbus/releases/latest 2>/dev/null \
        | grep '"tag_name"' | cut -d'"' -f4) || true
    if [ -z "$VERSION" ]; then
        echo "Error: No stable release found."
        echo "Options:"
        echo "  --prerelease           Install the latest pre-release"
        echo "  --version v2026.03.0   Install a specific version"
        exit 1
    fi
fi

STATBUS_DIR="${HOME}/statbus"
BINARY_URL="https://github.com/statisticsnorway/statbus/releases/download/${VERSION}/sb-${OS}-${ARCH}"

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
    # No --quiet on checkout: bug observed 2026-04-22 on rune canary
    # where a silent checkout failure (resolved on retry) hid its cause
    # behind --quiet, forcing operators to ssh in and re-run manually.
    # Keep fetch quiet (progress spam) but let checkout speak for itself.
    git fetch origin --tags --quiet
    git checkout "$VERSION"
else
    # FRESH: git clone creates the directory
    echo "Cloning StatBus repository..."
    git clone --depth 1 --branch "$VERSION" \
        https://github.com/statisticsnorway/statbus.git "$STATBUS_DIR"
    mv "${HOME}/sb.tmp" "${STATBUS_DIR}/sb"
    cd "$STATBUS_DIR"
    echo "Binary: $(./sb --version)"
    echo ""
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

if [ "$sb_rc" -eq 0 ]; then
    exit 0
fi

# ./sb install failed — gather a support bundle and write admin-UI state.
# Everything below is best-effort. If a step fails, continue to the next
# so the SYSTEM UNUSABLE banner always prints even when the DB is down or
# the bundle disk write fails.
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
