#!/bin/bash
# Phase two of 0-happy-install, executed as statbus AFTER the real fresh install.
# Use only the documented operator path. Never replace the whole .env.config:
# that would discard installer-owned signer settings and other live state.
set -euo pipefail
cd "$HOME/statbus"
for key in STATBUS_URL BROWSER_REST_URL SERVER_REST_URL DEBUG PUBLIC_DEBUG; do
    value=$(./sb dotenv -f /tmp/env-config get "$key")
    ./sb dotenv -f .env.config set "$key" "$value"
done
./sb config generate
for key in STATBUS_URL BROWSER_REST_URL SERVER_REST_URL DEBUG PUBLIC_DEBUG; do
    expected=$(./sb dotenv -f /tmp/env-config get "$key")
    actual=$(./sb dotenv -f .env.config get "$key")
    [ "$actual" = "$expected" ] || { echo "configuration mismatch for $key: expected='$expected' actual='$actual'"; exit 1; }
    generated_key="$key"
    [ "$key" != BROWSER_REST_URL ] || generated_key=PUBLIC_BROWSER_REST_URL
    actual=$(./sb dotenv -f .env get "$generated_key")
    [ "$actual" = "$expected" ] || { echo "generated configuration mismatch for $generated_key: expected='$expected' actual='$actual'"; exit 1; }
done
# sb restart recreates containers, so changed app environment takes effect.
./sb restart all
unit=statbus-upgrade@statbus.service
previous_invocation=$(systemctl --user show "$unit" -p InvocationID --value)
systemctl --user restart "$unit"
invocation=$(systemctl --user show "$unit" -p InvocationID --value)
[ -n "$invocation" ] && [ "$invocation" != "$previous_invocation" ] || { echo 'upgrade service did not start a new invocation'; exit 1; }
expected_channel=$(./sb dotenv -f .env get UPGRADE_CHANNEL)
[ "$expected_channel" = stable ] || { echo "operator phase changed default stable channel to '$expected_channel'"; exit 1; }
ready=false
for ((attempt=0; attempt<30; attempt++)); do
    if journalctl --user "_SYSTEMD_INVOCATION_ID=$invocation" --no-pager | grep -F "Upgrade service started (channel=$expected_channel,"; then
        ready=true
        break
    fi
    sleep 1
done
[ "$ready" = true ] || { echo "upgrade service did not report channel=$expected_channel in new invocation $invocation"; exit 1; }
container=$(docker compose ps -q app)
[ -n "$container" ] || { echo 'app container missing after configuration restart'; exit 1; }
for key in PUBLIC_BROWSER_REST_URL PUBLIC_DEBUG SERVER_REST_URL; do
    expected=$(./sb dotenv -f .env get "$key")
    docker inspect --format '{{range .Config.Env}}{{println .}}{{end}}' "$container" | grep -Fx "$key=$expected"
done
echo 'PASS: operator settings persisted, generated, and loaded by restarted app and upgrade service'
