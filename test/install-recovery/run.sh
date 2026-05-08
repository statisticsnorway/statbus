#!/bin/bash
# run.sh — dispatcher for install-recovery scenarios.
#
# Sourced by `./dev.sh test-install-recovery [args]`. Implements:
#   ./dev.sh test-install-recovery                 # all scenarios
#   ./dev.sh test-install-recovery --list          # list available
#   ./dev.sh test-install-recovery 09              # run by number
#   ./dev.sh test-install-recovery 09 07           # run several by number
#   ./dev.sh test-install-recovery bool-text       # run by name fragment
#   ./dev.sh test-install-recovery --keep-vm 09    # leave VM running on fail
#
# After all selected scenarios pass, writes the stamp
# tmp/install-recovery-test-passed-sha so a future ./sb release stable
# preflight can gate on it (opt-in).

set -euo pipefail

HARNESS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HARNESS_ROOT="$(cd "$HARNESS_DIR/../.." && pwd)"

SCENARIOS_DIR="$HARNESS_DIR/scenarios"
STAMP_FILE="$HARNESS_ROOT/tmp/install-recovery-test-passed-sha"

# Parse flags (anything starting with --) and positional args.
KEEP_VM=0
LIST_ONLY=0
SELECTORS=()
while [ $# -gt 0 ]; do
    case "$1" in
        --keep-vm) KEEP_VM=1 ;;
        --list)    LIST_ONLY=1 ;;
        --help|-h)
            cat <<EOF
Usage: ./dev.sh test-install-recovery [flags] [selector]...

Selectors:
  (none)         Run all scenarios
  09             Run scenario by number prefix
  bool-text      Run scenarios whose name contains the substring

Flags:
  --list         List available scenarios and exit
  --keep-vm      Leave VMs running on failure (debug)
  --help, -h     This message

Examples:
  ./dev.sh test-install-recovery                  # all scenarios
  ./dev.sh test-install-recovery --list           # see what's available
  ./dev.sh test-install-recovery 01 09            # baseline + bool-text
  ./dev.sh test-install-recovery worker-busy      # by name substring
EOF
            exit 0
            ;;
        --*)
            echo "Unknown flag: $1" >&2
            exit 2
            ;;
        *) SELECTORS+=("$1") ;;
    esac
    shift
done
export KEEP_VM

# Discover scenarios. (Avoid `mapfile` — bash 3.2 on macOS doesn't have it.)
ALL_SCENARIOS=()
while IFS= read -r f; do
    ALL_SCENARIOS+=("$f")
done < <(find "$SCENARIOS_DIR" -maxdepth 1 -type f -name '*.sh' | sort)

if [ "$LIST_ONLY" = "1" ]; then
    echo "Available scenarios:"
    for s in "${ALL_SCENARIOS[@]}"; do
        echo "  $(basename "$s" .sh)"
    done
    exit 0
fi

# Filter by selectors (numbers or substring matches).
SELECTED=()
if [ ${#SELECTORS[@]} -eq 0 ]; then
    SELECTED=("${ALL_SCENARIOS[@]}")
else
    for sel in "${SELECTORS[@]}"; do
        for s in "${ALL_SCENARIOS[@]}"; do
            base=$(basename "$s" .sh)
            # Match by numeric prefix (e.g. "09" matches "09-bool-text-regression")
            # or by substring of the name.
            if [[ "$base" =~ ^${sel}- ]] || [[ "$base" == *"$sel"* ]]; then
                SELECTED+=("$s")
                break
            fi
        done
    done
    if [ ${#SELECTED[@]} -eq 0 ]; then
        echo "No scenarios matched: ${SELECTORS[*]}" >&2
        echo "Run --list to see available." >&2
        exit 2
    fi
fi

mkdir -p "$HARNESS_ROOT/tmp"

# Run each selected scenario, capturing per-run logs.
PASS_COUNT=0
FAIL_COUNT=0
FAILED_NAMES=()

for s in "${SELECTED[@]}"; do
    base=$(basename "$s" .sh)
    vm_name="statbus-recovery-${base%%-*}"  # e.g. "01-happy-install" → vm "statbus-recovery-01"
    log_file="$HARNESS_ROOT/tmp/install-recovery-${base}.log"

    echo ""
    echo "═══════════════════════════════════════════════════════════════"
    echo "▶ Running scenario: $base (VM=$vm_name)"
    echo "  Log: $log_file"
    echo "═══════════════════════════════════════════════════════════════"

    if bash "$s" "$vm_name" 2>&1 | tee "$log_file"; then
        PASS_COUNT=$((PASS_COUNT + 1))
        echo "✓ PASS: $base"
    else
        FAIL_COUNT=$((FAIL_COUNT + 1))
        FAILED_NAMES+=("$base")
        echo "✗ FAIL: $base — see $log_file"
    fi
done

echo ""
echo "═══════════════════════════════════════════════════════════════"
echo "Summary: $PASS_COUNT passed, $FAIL_COUNT failed"
if [ "$FAIL_COUNT" -gt 0 ]; then
    echo "Failed scenarios:"
    for n in "${FAILED_NAMES[@]}"; do
        echo "  - $n"
    done
    exit 1
fi

# All passed — write stamp ONLY when ALL scenarios were selected
# (running a subset shouldn't claim full coverage).
if [ ${#SELECTORS[@]} -eq 0 ]; then
    git -C "$HARNESS_ROOT" rev-parse HEAD > "$STAMP_FILE"
    echo "Stamp recorded (install-recovery-test-passed-sha): $(cat "$STAMP_FILE")"
fi

echo "All scenarios passed."
