#!/usr/bin/env bash
# STATBUS-541 AC6: `./sb monitor template zabbix` imports into a real Zabbix 7.0
# (official images, throwaway compose project) through configuration.import,
# and the imported template carries the master item, the dependent items and
# the triggers. Run by hand or in CI where Docker is available:
#   bash test/monitor/zabbix-import-test.sh [path/to/sb]
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
SB="${1:-$ROOT/sb}"
PROJECT=statbus-zabbix-import-test
COMPOSE=(docker compose -p "$PROJECT" -f "$ROOT/test/monitor/zabbix-compose.yaml")
API=http://127.0.0.1:18541/api_jsonrpc.php
work="$(mktemp -d "${TMPDIR:-/tmp}/zabbix-import.XXXXXX")"
trap '"${COMPOSE[@]}" down -v >/dev/null 2>&1; rm -rf "$work"' EXIT

"$SB" monitor template zabbix > "$work/template.yaml" || { echo "FAIL: sb monitor template zabbix"; exit 1; }
"${COMPOSE[@]}" up -d >/dev/null 2>&1 || { echo "FAIL: zabbix compose up"; exit 1; }
rpc() { curl -s -H 'Content-Type: application/json-rpc' ${TOKEN:+-H "Authorization: Bearer $TOKEN"} -d "$1" "$API"; }
TOKEN=""
version=""
for _ in $(seq 1 60); do
    version=$(rpc '{"jsonrpc":"2.0","method":"apiinfo.version","params":{},"id":1}' 2>/dev/null | jq -r '.result // empty' 2>/dev/null)
    [ -n "$version" ] && break
    sleep 5
done
[ -n "$version" ] || { echo "FAIL: Zabbix API did not answer within 5 minutes"; exit 1; }
TOKEN=$(rpc '{"jsonrpc":"2.0","method":"user.login","params":{"username":"Admin","password":"zabbix"},"id":2}' | jq -r .result)
request=$(jq -n --rawfile src "$work/template.yaml" '{jsonrpc:"2.0",method:"configuration.import",id:3,params:{format:"yaml",source:$src,rules:{template_groups:{createMissing:true,updateExisting:true},templates:{createMissing:true,updateExisting:true},items:{createMissing:true,updateExisting:true},triggers:{createMissing:true,updateExisting:true}}}}')
import=$(rpc "$request")
if ! jq -e '.result == true' <<<"$import" >/dev/null; then
    echo "FAIL: Zabbix $version refused the template: $(jq -c '.error' <<<"$import")"
    exit 1
fi
read_back=$(rpc '{"jsonrpc":"2.0","method":"template.get","params":{"output":["host"],"selectItems":["key_"],"selectTriggers":["description"],"filter":{"host":["StatBus"]}},"id":4}')
items=$(jq '.result[0].items | length' <<<"$read_back")
triggers=$(jq '.result[0].triggers | length' <<<"$read_back")
master=$(jq '[.result[0].items[].key_ | select(. == "statbus.monitor")] | length' <<<"$read_back")
echo "Zabbix $version imported the StatBus template: $items items, $triggers triggers"
[ "$master" = 1 ] && [ "$items" -ge 10 ] && [ "$triggers" -ge 4 ] || { echo "FAIL: imported template is incomplete: $read_back"; exit 1; }
echo "zabbix import test: PASS"
