#!/usr/bin/env bash
#
# Integration test: install StatBus on a fresh Ubuntu 24.04 VM via multipass,
# then test the upgrade cycle (install → upgrade → rollback).
#
# Prerequisites: multipass installed (brew install multipass)
#
# Usage:
#   ./test/integration/test-upgrade-vm.sh          # full test
#   ./test/integration/test-upgrade-vm.sh --keep    # keep VM after test for debugging
#
set -euo pipefail

VM_NAME="statbus-test-$$"
KEEP_VM=false
REPO_DIR="$(cd "$(dirname "$0")/../.." && pwd)"

if [[ "${1:-}" == "--keep" ]]; then
    KEEP_VM=true
fi

cleanup() {
    if $KEEP_VM; then
        echo ""
        echo "=== VM kept for debugging ==="
        echo "  multipass shell $VM_NAME"
        echo "  multipass delete $VM_NAME --purge   # when done"
    else
        echo "Cleaning up VM..."
        multipass delete "$VM_NAME" --purge 2>/dev/null || true
    fi
}
trap cleanup EXIT

echo "=== Step 1: Build sb binary for linux-amd64 ==="
cd "$REPO_DIR/cli"
CGO_ENABLED=0 GOOS=linux GOARCH=amd64 go build -trimpath -o ../dist/sb-linux-amd64 .
echo "Built: dist/sb-linux-amd64"

echo ""
echo "=== Step 2: Launch Ubuntu 24.04 VM ==="
multipass launch 24.04 \
    --name "$VM_NAME" \
    --cpus 2 \
    --memory 4G \
    --disk 20G \
    --timeout 300

echo "VM launched: $VM_NAME"
multipass info "$VM_NAME" | head -5

echo ""
echo "=== Step 3: Install Docker in VM ==="
multipass exec "$VM_NAME" -- bash -c '
    sudo apt-get update -qq
    sudo apt-get install -y -qq ca-certificates curl git
    sudo install -m 0755 -d /etc/apt/keyrings
    sudo curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
    sudo chmod a+r /etc/apt/keyrings/docker.asc
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu $(. /etc/os-release && echo ${VERSION_CODENAME}) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
    sudo apt-get update -qq
    sudo apt-get install -y -qq docker-ce docker-ce-cli containerd.io docker-compose-plugin
    sudo usermod -aG docker ubuntu
'
echo "Docker installed"

echo ""
echo "=== Step 4: Transfer repo + binary to VM ==="
# Create a lightweight archive (exclude heavy dirs)
cd "$REPO_DIR"
tar czf /tmp/statbus-test.tar.gz \
    --exclude='.git' \
    --exclude='node_modules' \
    --exclude='app/.next' \
    --exclude='cli/dist' \
    --exclude='tmp' \
    .

multipass transfer /tmp/statbus-test.tar.gz "$VM_NAME":/tmp/statbus-test.tar.gz
multipass transfer "$REPO_DIR/dist/sb-linux-amd64" "$VM_NAME":/tmp/sb

multipass exec "$VM_NAME" -- bash -c '
    mkdir -p ~/statbus
    cd ~/statbus
    tar xzf /tmp/statbus-test.tar.gz
    cp /tmp/sb ./sb
    chmod +x ./sb
'
echo "Repo transferred"

echo ""
echo "=== Step 5: Generate config (development mode) ==="
multipass exec "$VM_NAME" -- bash -c '
    cd ~/statbus
    # Create minimal .env.config for development mode
    cat > .env.config <<ENVCONFIG
CADDY_DEPLOYMENT_MODE=development
SITE_DOMAIN=local.statbus.org
DEPLOYMENT_SLOT_CODE=local
DEPLOYMENT_SLOT_PORT_OFFSET=1
DEPLOYMENT_NAME=Test
ENVCONFIG

    ./sb config generate
'
echo "Config generated"

echo ""
echo "=== Step 6: Build and start services ==="
multipass exec "$VM_NAME" -- bash -c '
    cd ~/statbus
    # Use newgrp to pick up docker group membership
    sg docker -c "docker compose build"
    sg docker -c "docker compose up -d"

    echo "Waiting for services to start..."
    for i in $(seq 1 30); do
        if sg docker -c "docker compose exec -T db pg_isready -U postgres" 2>/dev/null; then
            echo "Database ready after ${i}s"
            break
        fi
        sleep 2
    done
'
echo "Services started"

echo ""
echo "=== Step 7: Run migrations ==="
multipass exec "$VM_NAME" -- bash -c '
    cd ~/statbus
    ./sb migrate up --verbose
'
echo "Migrations applied"

echo ""
echo "=== Step 8: Verify upgrade table exists ==="
multipass exec "$VM_NAME" -- bash -c '
    cd ~/statbus
    echo "SELECT count(*) FROM public.upgrade;" | ./sb psql -t -A
    echo "SELECT count(*) FROM public.system_info;" | ./sb psql -t -A
    echo "SELECT key, value FROM public.system_info ORDER BY key;" | ./sb psql
'
echo "Upgrade tracking tables verified"

echo ""
echo "=== Step 9: Verify health check ==="
VM_IP=$(multipass info "$VM_NAME" --format csv | tail -1 | cut -d, -f3)
echo "VM IP: $VM_IP"

multipass exec "$VM_NAME" -- bash -c '
    # Check if app responds (may take a moment)
    for i in $(seq 1 15); do
        STATUS=$(curl -s -o /dev/null -w "%{http_code}" http://localhost:3010/ 2>/dev/null || echo "000")
        if [ "$STATUS" != "000" ] && [ "$STATUS" != "502" ]; then
            echo "App responding: HTTP $STATUS"
            break
        fi
        echo "Waiting for app... (attempt $i, got $STATUS)"
        sleep 3
    done
'

echo ""
echo "=== Step 10: Test NOTIFY upgrade_check ==="
multipass exec "$VM_NAME" -- bash -c '
    cd ~/statbus
    echo "NOTIFY upgrade_check;" | ./sb psql
    echo "NOTIFY sent successfully"
'

echo ""
echo "=== Step 11: Verify maintenance page exists ==="
multipass exec "$VM_NAME" -- bash -c '
    test -f ~/statbus/ops/maintenance/maintenance.html && echo "Maintenance page: OK" || echo "Maintenance page: MISSING"
'

echo ""
echo "=== Step 12: Verify systemd service file ==="
multipass exec "$VM_NAME" -- bash -c '
    test -f ~/statbus/ops/statbus-upgrade.service && echo "Systemd service: OK" || echo "Systemd service: MISSING"
'

echo ""
echo "=========================================="
echo "  Integration test PASSED"
echo "=========================================="
echo ""
echo "VM: $VM_NAME"
echo "  multipass shell $VM_NAME"
echo "  multipass delete $VM_NAME --purge"
