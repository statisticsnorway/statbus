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
trap 'rc=$?; echo "" >&2; echo "install.sh FAILED at line $LINENO: $BASH_COMMAND (exit $rc)" >&2' ERR

# Parse arguments — install.sh-specific flags are consumed here;
# anything else is forwarded to ./sb install (e.g. --trust-github-user).
#
# --version vX.Y.Z   install the explicit tag
# --channel <name>   resolve version from channel. Valid names:
#                      stable     — latest non-prerelease via /releases/latest (default)
#                      prerelease — latest v*-rc.* via /releases API
#                      edge       — master HEAD, version string "sha-<short>"
# No flag            equivalent to --channel stable.
# --prerelease       REMOVED. Prints a rename notice and exits 1. Callers must
#                    switch to --channel prerelease (cloud.sh + standalone.sh
#                    already do so post-rc.62).
VERSION=""
CHANNEL=""
SB_INSTALL_ARGS=""
while [ $# -gt 0 ]; do
    case "$1" in
        --version) VERSION="$2"; shift 2 ;;
        --channel) CHANNEL="$2"; shift 2 ;;
        --prerelease)
            echo "Error: --prerelease was renamed. Use --channel prerelease instead." >&2
            exit 1
            ;;
        --trust-github-user) SB_INSTALL_ARGS="$SB_INSTALL_ARGS --trust-github-user $2"; shift 2 ;;
        *) echo "Unknown option: $1"; exit 1 ;;
    esac
done

# Default channel when neither --version nor --channel supplied.
if [ -z "$VERSION" ] && [ -z "$CHANNEL" ]; then
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
    # Edge channel: clone master (no release tag to pin), version string
    # becomes "sha-<short>". No release binary exists for arbitrary
    # master commits — `go` must be installed locally so ./dev.sh
    # build-sb can compile from source. Edge is the dev-oriented path;
    # production operators use stable or prerelease.
    if ! command -v go >/dev/null 2>&1; then
        echo "Error: --channel edge requires 'go' to build from source." >&2
        echo "  Install Go (https://go.dev/dl/), OR" >&2
        echo "  Use --channel prerelease for a pre-built binary." >&2
        exit 1
    fi
    if [ -d "$STATBUS_DIR/.git" ]; then
        echo "Updating existing installation (edge: master HEAD)..."
        cd "$STATBUS_DIR"
        git fetch origin master
        git checkout origin/master
    else
        echo "Cloning StatBus repository (edge: master)..."
        git clone --branch master \
            https://github.com/statisticsnorway/statbus.git "$STATBUS_DIR"
        cd "$STATBUS_DIR"
    fi
    # Short-SHA length matches .env COMMIT_SHORT8 and release.yaml
    # sha_short. Kept deliberately at 8 here so "sha-<short>" displays
    # are consistent across all install-time tooling.
    VERSION="sha-$(git rev-parse --short=8 HEAD)"
    echo "Edge version: $VERSION"
    echo "Building sb from source..."
    ./dev.sh build-sb >/dev/null
    echo "Binary: $(./sb --version)"
    echo ""
    # Edge path is fully resolved — skip the download-and-checkout
    # block below by jumping straight to the post-install steps.
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
        # No --force, no --quiet. install-verified moving tag was deleted
        # in rc.62; there is no moving tag to force past anymore. Silent
        # failures hid rune's rc.59 / rc.60 root causes — let fetch and
        # checkout print their own errors.
        git fetch origin --tags
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
