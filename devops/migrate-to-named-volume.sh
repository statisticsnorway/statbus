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
#   4. Lets Docker Compose create the named volume (Compose owns it)
#   5. Copies old bind mount data into the Compose-owned volume
#   6. Runs ./sb install (config, services, migrations, users)
#
# Old data is preserved at ./postgres/volumes/db/data/ as fallback.
# Rollback: revert compose file, restart with bind mount.

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

# 1. Stop services (old compose, bind mount)
echo "[1/6] Stopping services..."
docker compose --profile all down
echo ""

# 2. Pull latest code (new compose with named volume)
echo "[2/6] Pulling latest code..."
git fetch origin master
git checkout master
git merge --ff-only origin/master
echo ""

# 3. Download latest sb binary
echo "[3/6] Downloading sb binary..."
LATEST=$(curl -fsSL "https://api.github.com/repos/statisticsnorway/statbus/releases?per_page=1" \
    | grep -o '"tag_name":"[^"]*"' | head -1 | cut -d'"' -f4)
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

# 5. Let Compose create the named volume, then copy old data in
echo "[5/6] Migrating data to named volume..."
if [ -d "${OLD_DATA}" ] && [ "$(ls -A ${OLD_DATA} 2>/dev/null)" ]; then
    # Start db briefly so Compose creates the volume
    docker compose up -d db
    sleep 3
    docker compose stop db

    # Copy old bind mount data into the Compose-owned volume
    echo "  Copying data from ${OLD_DATA} to volume ${VOLUME}..."
    docker run --rm \
        -v "$(pwd)/${OLD_DATA}:/source:ro" \
        -v "${VOLUME}:/dest" \
        alpine sh -c "rm -rf /dest/* && cp -a /source/. /dest/"
    echo "  Data copied. Old data preserved at ${OLD_DATA} as fallback."
else
    echo "  No old bind mount data found — fresh installation."
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
echo "  curl -s http://localhost:$(grep CADDY_HTTP_PORT .env | cut -d= -f2)/ | head -1"
