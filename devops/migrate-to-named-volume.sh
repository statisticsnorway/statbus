#!/bin/bash
# Migrate a StatBus installation from bind-mount to named Docker volume.
# One-time script — NOT part of the sb binary.
#
# Usage:
#   ssh statbus_<code>@niue "cd statbus && bash devops/migrate-to-named-volume.sh"
#   Then as root: ssh root@niue "cd ~statbus_<code>/statbus && ./sb install"
#
# What it does:
#   1. Stops services (old compose with bind mount)
#   2. Pulls latest master code (new compose with named volume)
#   3. Downloads latest sb binary from GitHub Releases
#   4. Regenerates config
#   5. Creates named volume (Compose-owned) and copies old data in
#   6. Runs ./sb install (services, migrations, users)
#
# Old data is preserved at ./postgres/volumes/db/data/ as fallback.
# Rollback: git checkout the old compose file, restart with bind mount.

set -euo pipefail
cd "${HOME}/statbus"

echo "=== StatBus: Migrate to Named Volume ==="
echo ""

# Verify we're in a statbus directory
if [ ! -f docker-compose.yml ]; then
    echo "Error: not in a statbus directory (no docker-compose.yml)"
    exit 1
fi

# Read instance name from current .env
INSTANCE=$(grep COMPOSE_INSTANCE_NAME .env 2>/dev/null | cut -d= -f2 || echo "")
if [ -z "$INSTANCE" ]; then
    echo "Error: COMPOSE_INSTANCE_NAME not found in .env"
    exit 1
fi
VOLUME="${INSTANCE}-db-data"
OLD_DATA="./postgres/volumes/db/data"

echo "Instance: ${INSTANCE}"
echo "Volume:   ${VOLUME}"
echo "Old data: ${OLD_DATA}"
echo ""

# Idempotency: check if named volume already has PG data
if docker volume inspect "${VOLUME}" >/dev/null 2>&1; then
    HAS_DATA=$(docker run --rm -v "${VOLUME}:/data" alpine sh -c "test -f /data/PG_VERSION && echo yes || echo no")
    if [ "$HAS_DATA" = "yes" ]; then
        echo "Named volume ${VOLUME} already has PostgreSQL data."
        echo "Migration already done — running ./sb install to ensure everything is up to date."
        echo ""
        ./sb install
        exit 0
    fi
fi

# 1. Stop services (old compose, bind mount)
echo "[1/6] Stopping services..."
docker compose --profile all down
echo ""

# 2. Pull latest code (new compose with named volume)
echo "[2/6] Pulling latest code..."
# Stash any local changes (modified .env, configs) before checkout
git stash --include-untracked -m "migrate-to-named-volume: stash before checkout" 2>/dev/null || true
git fetch origin master
git checkout master
git merge --ff-only origin/master
# Restore stashed changes
git stash pop 2>/dev/null || true
echo ""

# 3. Download latest stable sb binary (skip pre-releases)
echo "[3/6] Downloading sb binary..."
LATEST=$(curl -fsSL "https://api.github.com/repos/statisticsnorway/statbus/releases?per_page=30" \
    | grep -o '"tag_name":"[^"]*"' | cut -d'"' -f4 | head -1)
if [ -z "$LATEST" ]; then
    echo "Error: could not determine latest release"
    exit 1
fi
curl -fsSL "https://github.com/statisticsnorway/statbus/releases/download/${LATEST}/sb-linux-amd64" -o sb
chmod +x sb
echo "Downloaded sb ${LATEST}"
./sb --version
echo ""

# 4. Regenerate config (adds VERSION, UPGRADE_* keys, creates backup/maintenance dirs)
echo "[4/6] Regenerating configuration..."
./sb config generate
echo ""

# 5. Create named volume (Compose-owned) and copy old data in
echo "[5/6] Migrating data to named volume..."

# Validate old data has PostgreSQL structure
if [ -d "${OLD_DATA}" ] && [ -f "${OLD_DATA}/PG_VERSION" ]; then
    PG_VER=$(cat "${OLD_DATA}/PG_VERSION")
    echo "  Found PostgreSQL ${PG_VER} data in ${OLD_DATA}"

    # Let Compose create the volume by starting db briefly
    echo "  Creating Compose-owned volume..."
    docker compose up -d db

    # Wait for volume to exist (not just sleep — verify it)
    for i in $(seq 1 30); do
        if docker volume inspect "${VOLUME}" >/dev/null 2>&1; then
            break
        fi
        sleep 1
    done

    if ! docker volume inspect "${VOLUME}" >/dev/null 2>&1; then
        echo "  Error: volume ${VOLUME} was not created after 30 seconds"
        exit 1
    fi

    docker compose stop db

    # Copy old bind mount data into the Compose-owned volume
    echo "  Copying data from ${OLD_DATA} to volume ${VOLUME}..."
    if ! docker run --rm \
        -v "$(pwd)/${OLD_DATA}:/source:ro" \
        -v "${VOLUME}:/dest" \
        alpine sh -c "rm -rf /dest/* && cp -a /source/. /dest/"; then
        echo "  Error: data copy failed!"
        echo "  Old data is still intact at ${OLD_DATA}"
        exit 1
    fi

    # Verify copy succeeded
    COPIED_VER=$(docker run --rm -v "${VOLUME}:/data" alpine cat /data/PG_VERSION 2>/dev/null || echo "")
    if [ "${COPIED_VER}" != "${PG_VER}" ]; then
        echo "  Error: PG_VERSION mismatch after copy (expected ${PG_VER}, got ${COPIED_VER})"
        exit 1
    fi

    echo "  Data migrated successfully (PG ${PG_VER})."
    echo "  Old data preserved at ${OLD_DATA} as fallback."
else
    echo "  No old PostgreSQL data found — fresh installation."
fi
echo ""

# 6. Run sb install (starts services, applies migrations, creates users)
echo "[6/6] Running sb install..."
./sb install

echo ""
echo "=== Migration complete ==="
echo ""
echo "Next step (as root):"
echo "  ssh root@niue \"cd ~$(whoami)/statbus && ./sb install\""
echo ""
echo "Verify:"
echo "  ./sb upgrade list"
