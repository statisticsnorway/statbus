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
echo "scenario helper resolution tests: PASS"
