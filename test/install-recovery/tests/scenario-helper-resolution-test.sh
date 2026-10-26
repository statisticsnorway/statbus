#!/bin/bash
# Offline syntax and cross-file function-resolution test. No VM, Docker or DB.
set -euo pipefail

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HARNESS_DIR="$(cd "$TEST_DIR/.." && pwd)"
LIB_DIR="$HARNESS_DIR/lib"
SCENARIO_DIR="$HARNESS_DIR/scenarios"

for script in "$LIB_DIR"/*.sh "$SCENARIO_DIR"/*.sh; do
    bash -n "$script"
done
echo "PASS: every library and scenario parses in bash -n mode"

# configure-smoke-instance.sh is an executable remote payload rather than a
# source-only function library. Every other lib/*.sh file is sourced exactly as
# scenarios source it, then declare -F verifies calls without executing a VM.
source_args=()
for library in "$LIB_DIR"/*.sh; do
    [ "$(basename "$library")" = configure-smoke-instance.sh ] && continue
    source_args+=("$library")
done

mapfile_compat() {
    while IFS= read -r line; do
        [ -n "$line" ] && printf '%s\n' "$line"
    done
}

# Match the literal shell token rather than expanding this test process's VM_NAME.
# shellcheck disable=SC2016
calls=$(sed -nE 's/^[[:space:]]*([A-Za-z_][A-Za-z0-9_]*)[[:space:]]+"\$VM_NAME"([[:space:]]|$).*/\1/p' \
    "$SCENARIO_DIR"/*.sh | sort -u | mapfile_compat)

failures=0
while IFS= read -r function_name; do
    [ -n "$function_name" ] || continue
    if ! bash -c '
        set -euo pipefail
        function_name=$1
        shift
        export HCLOUD_TOKEN=offline-static-resolution
        for library in "$@"; do source "$library"; done
        declare -F "$function_name" >/dev/null
    ' bash "$function_name" "${source_args[@]}"; then
        echo "FAIL: scenario call '$function_name \"\$VM_NAME\"' has no function in lib/*.sh" >&2
        failures=$((failures + 1))
    fi
done <<< "$calls"

[ "$failures" -eq 0 ] || exit 1
echo "PASS: every name \"\$VM_NAME\" scenario call resolves to a sourced library function"

# ─────────────────────────────────────────────────────────────────────────
# STATBUS-527 B3: upgrade_unit_name call-site scope.
#
# The helper is defined in lib/assertions.sh and probes the guest over
# VM_EXEC, so a call site is valid only when (a) the calling file has already
# sourced assertions.sh and (b) the call runs on the HOST. Three defect
# classes violated this: arcs calling the helper before its source line
# (exit 127 under set -euo pipefail), arcs caching the name before the guest
# exists (VM_EXEC fails, the legacy-name fallback binds the wrong unit on
# candidate bases), and a call inside a quoted remote heredoc (executes on
# the guest, where the function is undefined). The checks below reject all
# three statically and then prove the helper still resolves both eras.
# ─────────────────────────────────────────────────────────────────────────
ARC_DIR="$HARNESS_DIR/arcs"

for script in "$ARC_DIR"/*.sh; do
    bash -n "$script"
done
echo "PASS: every arc parses in bash -n mode"

# Check 1: a top-level (column 0) upgrade_unit_name call executes at source
# time of the calling script, so it must come AFTER that file's own
# `source .../assertions.sh` line. Files that never source assertions.sh
# (function libraries whose callers source it, executable remote payloads)
# must have no top-level calls at all. Function bodies are indented in this
# codebase, so a column-0 occurrence is a top-level execution. Heredoc bodies
# (quoted or not) are content, not call sites: the scanner tracks every
# heredoc and skips its body.
scope_failures=0
for script in "$ARC_DIR"/*.sh "$SCENARIO_DIR"/*.sh "$LIB_DIR"/*.sh; do
    source_line=$(grep -n 'source .*assertions\.sh' "$script" | head -1 | cut -d: -f1 || true)
    bad=$(awk -v src="${source_line:-0}" -v sq="'" '
        function ltrim(s) { sub(/^[ \t]+/, "", s); return s }
        {
            line=$0
            if (inhd) {
                t=line
                if (dash) sub(/^\t+/, "", t)
                # A heredoc can also live inside a single-quoted ssh argument;
                # its terminator line then ends with the closing quote (for
                # example EOF followed by a single quote). Accept trailing
                # quote/paren characters so pairing survives that construction.
                sub(/['"'"'\")]+$/, "", t)
                if (t == word) inhd=0
                next
            }
            if (ltrim(line) ~ /^#/) next
            re="<<-?[ \t]*[\"]?" sq "?[A-Za-z_][A-Za-z0-9_]*[\"]?" sq "?"
            rest=line
            while (match(rest, re)) {
                pre = (RSTART > 1) ? substr(rest, RSTART-1, 1) : ""
                tok = substr(rest, RSTART, RLENGTH)
                rest = substr(rest, RSTART + RLENGTH)
                if (pre == "<") continue   # herestring <<< or << nested in another <
                dash = (tok ~ /<<-/) ? 1 : 0
                word=tok
                sub(/<<-?[ \t]*/, "", word)
                gsub(/"/, "", word); gsub(sq, "", word)
                inhd=1
                break
            }
            if (line ~ /^[^ \t]/ && line ~ /upgrade_unit_name/ && line !~ /upgrade_unit_name\(\)/) {
                if (src == 0 || FNR < src) printf "%d\n", FNR
            }
        }
    ' "$script")
    if [ -n "$bad" ]; then
        echo "FAIL: $script calls upgrade_unit_name at top level before assertions.sh is sourced (lines: $(echo $bad | tr '\n' ' '))" >&2
        scope_failures=$((scope_failures + 1))
    fi
done
[ "$scope_failures" -eq 0 ] || exit 1
echo "PASS: every top-level upgrade_unit_name call comes after the file's assertions.sh source line"

# Check 2: no upgrade_unit_name call inside a QUOTED heredoc. A quoted
# heredoc ships its body literally, typically to `ssh ... bash -s`, so the
# call would execute on the guest where the helper is undefined. Unquoted
# heredocs expand on the host and stay valid; the scanner therefore tracks
# every heredoc (quoted or not, <<- included) and flags only quoted bodies.
heredoc_failures=0
for script in "$ARC_DIR"/*.sh "$SCENARIO_DIR"/*.sh "$LIB_DIR"/*.sh; do
    bad=$(awk -v sq="'" '
        function ltrim(s) { sub(/^[ \t]+/, "", s); return s }
        {
            line=$0
            if (inhd) {
                t=line
                if (dash) sub(/^\t+/, "", t)
                # A heredoc can also live inside a single-quoted ssh argument;
                # its terminator line then ends with the closing quote (for
                # example EOF followed by a single quote). Accept trailing
                # quote/paren characters so pairing survives that construction.
                sub(/['"'"'\")]+$/, "", t)
                if (t == word) { inhd=0; next }
                if (quoted && line ~ /upgrade_unit_name/ && ltrim(line) !~ /^#/)
                    printf "%d\n", FNR
                next
            }
            if (ltrim(line) ~ /^#/) next
            re="<<-?[ \t]*[\"]?" sq "?[A-Za-z_][A-Za-z0-9_]*[\"]?" sq "?"
            rest=line
            while (match(rest, re)) {
                pre = (RSTART > 1) ? substr(rest, RSTART-1, 1) : ""
                tok = substr(rest, RSTART, RLENGTH)
                rest = substr(rest, RSTART + RLENGTH)
                if (pre == "<") continue   # herestring <<< or << nested in another <
                quoted = (tok ~ /"/ || index(tok, sq) > 0) ? 1 : 0
                dash = (tok ~ /<<-/) ? 1 : 0
                word=tok
                sub(/<<-?[ \t]*/, "", word)
                gsub(/"/, "", word); gsub(sq, "", word)
                inhd=1
                break
            }
        }
    ' "$script")
    if [ -n "$bad" ]; then
        echo "FAIL: $script calls upgrade_unit_name inside a quoted heredoc (guest-side, helper undefined) at lines: $(echo $bad | tr '\n' ' ')" >&2
        heredoc_failures=$((heredoc_failures + 1))
    fi
done
[ "$heredoc_failures" -eq 0 ] || exit 1
echo "PASS: no upgrade_unit_name call sits inside a quoted (guest-executed) heredoc"

# Check 3 (positive): the helper itself resolves both eras. A guest carrying
# the renamed unit file (candidate path) yields statbus-upgrader@; a guest
# without it (pre-rename path) yields statbus-upgrade@.
if ! bash -c '
    set -euo pipefail
    export HCLOUD_TOKEN=offline-static-resolution
    for library in "$@"; do source "$library"; done
    VM_EXEC() { return "$STUB_RC"; }
    STUB_RC=0
    got=$(upgrade_unit_name)
    [ "$got" = "statbus-upgrader@statbus.service" ] || { echo "candidate path resolved to $got" >&2; exit 1; }
    STUB_RC=1
    got=$(upgrade_unit_name)
    [ "$got" = "statbus-upgrade@statbus.service" ] || { echo "pre-rename path resolved to $got" >&2; exit 1; }
' bash "${source_args[@]}"; then
    echo "FAIL: upgrade_unit_name no longer resolves the candidate and pre-rename unit names" >&2
    exit 1
fi
echo "PASS: upgrade_unit_name resolves statbus-upgrader@ on candidate bases and statbus-upgrade@ on pre-rename bases"

# Check 4 (positive): scripts that bind the upgrader unit name once at top
# level run on candidate installs, so every such binding must name the
# post-rename unit. Count them too, so an empty search space cannot pass.
# A top-level binding whose whole value is $(upgrade_unit_name) is the B3b
# defect class itself: it executes before the guest exists, and a name cached
# once cannot survive the mid-run unit rename. Per-call resolution inside a
# later command remains the valid pattern.
legacy_bindings=$(grep -rnE '^[A-Za-z_][A-Za-z0-9_]*="[^"]*statbus-upgrade@' "$ARC_DIR" "$SCENARIO_DIR" || true)
if [ -n "$legacy_bindings" ]; then
    echo "FAIL: top-level unit bindings name the pre-rename unit on candidate bases:" >&2
    echo "$legacy_bindings" >&2
    exit 1
fi
cached_bindings=$(grep -rnE '^[A-Za-z_][A-Za-z0-9_]*="?\$\(upgrade_unit_name\)"?[ \t]*$' "$ARC_DIR" "$SCENARIO_DIR" || true)
if [ -n "$cached_bindings" ]; then
    echo "FAIL: top-level bindings cache \$(upgrade_unit_name) before the guest exists (B3b class):" >&2
    echo "$cached_bindings" >&2
    exit 1
fi
literal_count=$(grep -rhE '^[A-Za-z_][A-Za-z0-9_]*="(\\\$HOME/[^"]*)?statbus-upgrader@statbus\.service' "$ARC_DIR" "$SCENARIO_DIR" | wc -l | tr -d ' ')
[ "$literal_count" -ge 12 ] || {
    echo "FAIL: expected at least 12 top-level candidate-literal unit bindings (the B3 arcs), found $literal_count" >&2
    exit 1
}
echo "PASS: $literal_count top-level unit bindings name the candidate unit statbus-upgrader@statbus.service; none name the legacy unit"

# Check 5 (positive): the rename-crossing path (0-happy-upgrade installs a
# pre-rename release and crosses the rename mid-scenario) must keep resolving
# per call, never from a cached top-level binding.
per_call_count=$(grep -c '\$(upgrade_unit_name)' "$SCENARIO_DIR/0-happy-upgrade.sh" || true)
[ "$per_call_count" -ge 1 ] || {
    echo "FAIL: 0-happy-upgrade.sh lost its per-call upgrade_unit_name resolution across the rename" >&2
    exit 1
}
if grep -qE '^[A-Za-z_][A-Za-z0-9_]*="?\$\(upgrade_unit_name\)' "$SCENARIO_DIR/0-happy-upgrade.sh"; then
    echo "FAIL: 0-happy-upgrade.sh caches the unit name at top level although the unit is renamed mid-scenario" >&2
    exit 1
fi
echo "PASS: 0-happy-upgrade.sh resolves the unit per call ($per_call_count sites) across the mid-scenario rename"

echo "scenario helper resolution tests: PASS"
