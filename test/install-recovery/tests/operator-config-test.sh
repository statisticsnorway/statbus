#!/bin/bash
# Execute the real post-install script against a local filesystem and command
# fixtures. Runtime checks are simulated, not evidence from Docker or systemd.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
TMP_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/statbus-operator.XXXXXX")
trap 'rm -rf "$TMP_ROOT"' EXIT
mkdir -p "$TMP_ROOT/home/statbus" "$TMP_ROOT/bin"
export HOME="$TMP_ROOT/home" TRACE="$TMP_ROOT/trace" INVOCATION_FILE="$TMP_ROOT/invocation"
sed "s|/tmp/env-config|$TMP_ROOT/input.env|g" "$ROOT/test/install-recovery/lib/configure-smoke-instance.sh" > "$TMP_ROOT/operator.sh"
cat > "$TMP_ROOT/input.env" <<'CONFIG'
STATBUS_URL=https://statbus-test.local
BROWSER_REST_URL=https://statbus-test.local
SERVER_REST_URL=http://proxy:80
DEBUG=false
PUBLIC_DEBUG=false
CONFIG
cat > "$HOME/statbus/sb" <<'MOCK'
#!/usr/bin/env python3
import os,sys
from pathlib import Path
args=sys.argv[1:]
with open(os.environ['TRACE'],'a') as out: out.write('sb:'+ ' '.join(args)+'\n')
def read(path): return dict(line.split('=',1) for line in Path(path).read_text().splitlines() if '=' in line)
def write(path,values): Path(path).write_text(''.join(k+'='+v+'\n' for k,v in values.items()))
fault=os.getenv('FAULT','')
if args[0]=='dotenv':
    path,op,key=args[2:5]; values=read(path)
    if op=='get': print(values[key])
    else:
        if fault!='persisted': values[key]=args[5]
        write(path,values)
elif args[:2]==['config','generate']:
    values=read('.env.config');values['PUBLIC_BROWSER_REST_URL']=values.pop('BROWSER_REST_URL');values['UPGRADE_CHANNEL']='stable'
    if fault=='generated': values['STATBUS_URL']='wrong'
    write('.env',values)
elif args[:2]==['restart','all']:
    if fault=='restart': sys.exit(41)
else: sys.exit(99)
MOCK
cat > "$TMP_ROOT/bin/systemctl" <<'MOCK'
#!/bin/bash
set -eu
case "$*" in
    *InvocationID*) cat "$INVOCATION_FILE" ;;
    *restart*) echo new > "$INVOCATION_FILE" ;;
    *) exit 99 ;;
esac
MOCK
cat > "$TMP_ROOT/bin/journalctl" <<'MOCK'
#!/bin/bash
if [ "${FAULT:-}" = daemon ]; then echo 'Upgrade service started (channel=local, interval=1h)'; else echo 'Upgrade service started (channel=stable, interval=1h)'; fi
MOCK
cat > "$TMP_ROOT/bin/docker" <<'MOCK'
#!/bin/bash
if [ "$1" = compose ]; then echo app-id; exit; fi
if [ "${FAULT:-}" = runtime ]; then echo PUBLIC_DEBUG=true; else echo PUBLIC_DEBUG=false; fi
printf '%s\n' 'PUBLIC_BROWSER_REST_URL=https://statbus-test.local' 'SERVER_REST_URL=http://proxy:80'
MOCK
cat > "$TMP_ROOT/bin/sleep" <<'MOCK'
#!/bin/bash
exit 0
MOCK
chmod +x "$HOME/statbus/sb" "$TMP_ROOT/bin/"*
export PATH="$TMP_ROOT/bin:$PATH"
reset_fixture() {
    cat > "$HOME/statbus/.env.config" <<'CONFIG'
CADDY_DEPLOYMENT_MODE=private
SITE_DOMAIN=statbus-test.local
DEPLOYMENT_SLOT_NAME=Install Test
DEPLOYMENT_SLOT_CODE=test
DEPLOYMENT_SLOT_PORT_OFFSET=1
UPGRADE_TRUSTED_SIGNER_jhf=preserve-this
STATBUS_URL=before-tuning
CONFIG
    echo old > "$INVOCATION_FILE"
    : > "$TRACE"
}
reset_fixture
bash "$TMP_ROOT/operator.sh" > "$TMP_ROOT/output"
grep -Fxq UPGRADE_TRUSTED_SIGNER_jhf=preserve-this "$HOME/statbus/.env.config"
if grep -q '^UPGRADE_CHANNEL=' "$HOME/statbus/.env.config"; then echo 'FAIL: operator phase seeded a channel'; exit 1; fi
config_line=$(grep -n '^sb:config generate' "$TRACE" | cut -d: -f1)
restart_line=$(grep -n '^sb:restart all' "$TRACE" | cut -d: -f1)
[ "$config_line" -lt "$restart_line" ]
echo 'PASS: operator tuning preserves signer state and default channel, generates before restart, and checks consumers'
for fault in persisted generated restart runtime daemon; do
    reset_fixture
    if FAULT="$fault" bash "$TMP_ROOT/operator.sh" > "$TMP_ROOT/output" 2>&1; then
        echo "FAIL: accepted $fault fault"; exit 1
    fi
    echo "PASS: rejected $fault fault"
done
echo 'operator-config tests: PASS'
