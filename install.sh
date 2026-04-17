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
    echo "Checking for latest pre-release..."
    # Fetch enough releases to cover all recent RCs, extract tag names,
    # filter to RC tags, sort by CalVer+RC numerically, pick the highest.
    # GitHub's API does not guarantee version order. `sort -V` is unavailable
    # on some servers, so we use awk to extract numeric components and sort
    # by year, month, patch, rc-number — works everywhere.
    VERSION=$(curl -sL "https://api.github.com/repos/statisticsnorway/statbus/releases?per_page=50" 2>/dev/null \
        | grep '"tag_name"' | cut -d'"' -f4 | grep '\-rc\.' \
        | awk -F'[v.\\-]' '{print $2*1e8 + $3*1e6 + $4*1e4 + $6+0, $0}' \
        | sort -n | tail -1 | awk '{print $2}') || true
    if [ -z "$VERSION" ]; then
        echo "Error: No pre-release found."
        exit 1
    fi
    echo "Latest pre-release: $VERSION"
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
    git fetch origin --tags --quiet
    git checkout "$VERSION" --quiet
    exec ./sb install $SB_INSTALL_ARGS
else
    # FRESH: git clone creates the directory
    echo "Cloning StatBus repository..."
    git clone --depth 1 --branch "$VERSION" \
        https://github.com/statisticsnorway/statbus.git "$STATBUS_DIR"
    mv "${HOME}/sb.tmp" "${STATBUS_DIR}/sb"
    cd "$STATBUS_DIR"
    echo "Binary: $(./sb --version)"
    echo ""
    exec ./sb install $SB_INSTALL_ARGS
fi
