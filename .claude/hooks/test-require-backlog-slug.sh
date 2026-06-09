#!/bin/bash
# Test suite for .claude/hooks/require-backlog-slug.sh
#   bash .claude/hooks/test-require-backlog-slug.sh
# Exit 0: all pass. Exit 1: any fail.
set -u

HOOK="$(cd "$(dirname "$0")" && pwd)/require-backlog-slug.sh"
[ -f "$HOOK" ] || { echo "ERROR: hook not found at $HOOK"; exit 1; }
bash -n "$HOOK" || { echo "SYNTAX ERROR in $HOOK"; exit 1; }

PASS=0; FAIL=0
dec() { jq -r '.hookSpecificOutput.permissionDecision // "allow"' <<<"$1" 2>/dev/null || echo allow; }
ok_allow(){ local l="$1" p="$2" o d; o=$(printf '%s' "$p" | bash "$HOOK" 2>/dev/null); d=$(dec "$o");
  if [[ "$d" == allow ]]; then PASS=$((PASS+1)); printf '[allow OK ] %s\n' "$l"; else FAIL=$((FAIL+1)); printf '[%s FAIL] %s (want allow)\n' "$d" "$l"; fi; }
ok_deny(){ local l="$1" p="$2" o d; o=$(printf '%s' "$p" | bash "$HOOK" 2>/dev/null); d=$(dec "$o");
  if [[ "$d" == deny ]]; then PASS=$((PASS+1)); printf '[deny  OK ] %s\n' "$l"; else FAIL=$((FAIL+1)); printf '[%s FAIL] %s (want deny)\n' "$d" "$l"; fi; }

echo "── task_create: title slug enforcement ──"
ok_allow "good slug"            '{"tool_name":"mcp__backlog__task_create","tool_input":{"title":"rune-wedge: route migrate-up failure to recovery"}}'
ok_deny  "no slug prefix"       '{"tool_name":"mcp__backlog__task_create","tool_input":{"title":"Fix the rune wedge"}}'
ok_deny  "uppercase first char" '{"tool_name":"mcp__backlog__task_create","tool_input":{"title":"Rune: fix it"}}'
ok_deny  "slug too short (<3)"  '{"tool_name":"mcp__backlog__task_create","tool_input":{"title":"ab: too short"}}'
ok_deny  "no space after colon" '{"tool_name":"mcp__backlog__task_create","tool_input":{"title":"good-slug:no-space"}}'
ok_deny  "leading hyphen"       '{"tool_name":"mcp__backlog__task_create","tool_input":{"title":"-bad: leading hyphen"}}'

echo "── task_edit: enforce only when title is set ──"
ok_allow "edit good title"      '{"tool_name":"mcp__backlog__task_edit","tool_input":{"id":"STATBUS-1","title":"slug-ok: renamed task"}}'
ok_deny  "edit bad title"       '{"tool_name":"mcp__backlog__task_edit","tool_input":{"id":"STATBUS-1","title":"No slug here"}}'
ok_allow "edit notes only"      '{"tool_name":"mcp__backlog__task_edit","tool_input":{"id":"STATBUS-1","notesAppend":["x"]}}'
ok_allow "edit status only"     '{"tool_name":"mcp__backlog__task_edit","tool_input":{"id":"STATBUS-1","status":"Done"}}'

echo "── passthrough (not gated) ──"
ok_allow "harness TaskCreate"   '{"tool_name":"TaskCreate","tool_input":{"subject":"whatever"}}'
ok_allow "backlog task_view"    '{"tool_name":"mcp__backlog__task_view","tool_input":{"id":"STATBUS-1"}}'
ok_allow "Bash"                 '{"tool_name":"Bash","tool_input":{"command":"ls"}}'

echo "── disabled via env ──"
o=$(printf '%s' '{"tool_name":"mcp__backlog__task_create","tool_input":{"title":"No slug"}}' | HOOK_ENABLED_REQUIRE_BACKLOG_SLUG=0 bash "$HOOK" 2>/dev/null); d=$(dec "$o")
if [[ "$d" == allow ]]; then PASS=$((PASS+1)); printf '[allow OK ] HOOK_ENABLED=0 lets a bad title pass\n'; else FAIL=$((FAIL+1)); printf '[%s FAIL] disabled (want allow)\n' "$d"; fi

TOTAL=$((PASS+FAIL)); echo "────────────────────────────────────────"
if [[ $FAIL -eq 0 ]]; then echo "ALL GREEN: $PASS / $TOTAL tests passed"; exit 0; else echo "FAILED: $FAIL / $TOTAL ($PASS passed)"; exit 1; fi
