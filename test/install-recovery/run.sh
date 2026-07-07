#!/bin/bash
# run.sh — dispatcher for install-recovery scenarios.
#
# Sourced by `./dev.sh test-install-recovery [args]`. Implements:
#   ./dev.sh test-install-recovery                 # all scenarios
#   ./dev.sh test-install-recovery --list          # list available
#   ./dev.sh test-install-recovery 3-postswap-worker-ddl-deadlock   # one scenario by slug
#   ./dev.sh test-install-recovery 1-boot 5-install    # several by phase prefix
#   ./dev.sh test-install-recovery bool-text       # run by name fragment
#   ./dev.sh test-install-recovery --keep-vm 5-install-seed-on-populated   # leave VM running on fail
#
# After all selected scenarios pass, writes the stamp
# tmp/install-recovery-test-passed-sha so a future ./sb release stable
# preflight can gate on it (opt-in).

set -euo pipefail

HARNESS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HARNESS_ROOT="$(cd "$HARNESS_DIR/../.." && pwd)"

SCENARIOS_DIR="$HARNESS_DIR/scenarios"
STAMP_FILE="$HARNESS_ROOT/tmp/install-recovery-test-passed-sha"

# Marker for known-RED reproducers (deliberate failing scenarios that prove an
# open product bug — e.g. STATBUS-017). A scenario file containing this marker is
# EXCLUDED from the default/full run and from broad phase-prefix runs, so the
# strict-green gating suite (the stamp below is written ONLY on a full run) never
# goes red on an expected failure. Such a scenario still runs when a selector
# names it specifically (a non-phase-prefix substring — its slug or a unique
# fragment), which is how an operator captures the bug on demand.
SKIP_DEFAULT_MARKER="HARNESS_SKIP_DEFAULT"
_is_skip_default() { grep -q "$SKIP_DEFAULT_MARKER" "$1" 2>/dev/null; }

# Append a scenario path to SELECTED unless it is already there. Selection MUST be
# duplicate-free: a repeated scenario becomes two matrix jobs with the same name →
# two Hetzner VMs both named "statbus-recovery-<scenario>" → an `hcloud server
# create` name collision that fails BOTH jobs (and the scenario the operator
# actually wanted may never run). This dedup is the single source of truth the CI
# matrix consumes via --print-selected, so it protects the matrix too.
_add_selected() {
    local cand="$1" existing
    if [ ${#SELECTED[@]} -gt 0 ]; then
        for existing in "${SELECTED[@]}"; do
            [ "$existing" = "$cand" ] && return 0
        done
    fi
    SELECTED+=("$cand")
}

# Parse flags (anything starting with --) and positional args.
KEEP_VM=0
LIST_ONLY=0
PRINT_SELECTED=0
SELECTORS=()
while [ $# -gt 0 ]; do
    case "$1" in
        --keep-vm) KEEP_VM=1 ;;
        --list)    LIST_ONLY=1 ;;
        --print-selected) PRINT_SELECTED=1 ;;
        --help|-h)
            cat <<EOF
Usage: ./dev.sh test-install-recovery [flags] [selector]...

Selectors:
  (none)         Run all scenarios
  2-preswap      Run a phase (prefix match) or a full slug; or any name fragment
  bool-text      Run scenarios whose name contains the substring

Flags:
  --list             List available scenarios and exit
  --print-selected   Print the base names the SAME selection would run (one per
                     line) and exit WITHOUT running anything. Honours selectors
                     and the known-RED exclusion — the CI matrix consumes this so
                     scenario selection lives in exactly one place (here).
  --keep-vm          Leave VMs running on failure (debug)
  --help, -h         This message

Examples:
  ./dev.sh test-install-recovery                  # all scenarios
  ./dev.sh test-install-recovery --list           # see what's available
  ./dev.sh test-install-recovery 0-happy 3-postswap            # the happy baselines + every post-swap scenario
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
        if _is_skip_default "$s"; then
            echo "  $(basename "$s" .sh)   [known-RED — on-demand only, excluded from default run]"
        else
            echo "  $(basename "$s" .sh)"
        fi
    done
    exit 0
fi

# Filter by selectors (phase prefix or substring matches).
SELECTED=()
if [ ${#SELECTORS[@]} -eq 0 ]; then
    # Default/full run: every scenario EXCEPT the known-RED reproducers, so the
    # strict-green gating suite stays green (the stamp is gated on this branch).
    for s in "${ALL_SCENARIOS[@]}"; do
        if _is_skip_default "$s"; then
            # Progress notice → stderr, NOT stdout. --print-selected emits the
            # chosen names on stdout as DATA (the CI matrix captures it); a
            # notice on stdout here would become bogus matrix entries → 2
            # always-failing jobs → the gate could never go green.
            echo "  (excluding known-RED reproducer from default run: $(basename "$s" .sh))" >&2
            continue
        fi
        SELECTED+=("$s")
    done
else
    for sel in "${SELECTORS[@]}"; do
        # EXACT basename match wins outright: a selector that names a specific
        # scenario selects ONLY that scenario, never a phase-prefix sibling.
        # Without this, a selector like "2-preswap-checkout-kill" would match the
        # `^<sel>-` prefix of a longer sibling (historically the since-retired
        # "2-preswap-checkout-kill-legacy", which sorted FIRST since '-' < '.')
        # and — with the old first-match-then-`break` — resolve to the WRONG
        # scenario while the intended exact file never ran. An exact name also
        # legitimately selects a known-RED reproducer (it is named specifically).
        exact=""
        for s in "${ALL_SCENARIOS[@]}"; do
            [ "$(basename "$s" .sh)" = "$sel" ] && { exact="$s"; break; }
        done
        if [ -n "$exact" ]; then
            _add_selected "$exact"
            continue
        fi
        # No exact match: treat the selector as a phase prefix ("2-preswap" →
        # EVERY "2-preswap-*") or a name substring, and select ALL matches — not
        # just the first (the old `break` silently ran only one of a phase group).
        for s in "${ALL_SCENARIOS[@]}"; do
            base=$(basename "$s" .sh)
            phase_match=0; substr_match=0
            [[ "$base" =~ ^${sel}- ]] && phase_match=1
            [[ "$base" == *"$sel"* ]] && substr_match=1
            if [ "$phase_match" = 0 ] && [ "$substr_match" = 0 ]; then
                continue
            fi
            # A known-RED reproducer is pulled in ONLY by a selector that names it
            # specifically (the exact name above, or a non-phase-prefix substring).
            # A bare phase prefix (e.g. "3-postswap") must NOT drag it into a group
            # run, or the group goes red on an expected failure.
            if _is_skip_default "$s" && [ "$phase_match" = 1 ]; then
                continue
            fi
            _add_selected "$s"
        done
    done
    if [ ${#SELECTED[@]} -eq 0 ]; then
        echo "No scenarios matched: ${SELECTORS[*]}" >&2
        echo "Run --list to see available." >&2
        exit 2
    fi
fi

# --print-selected: emit the chosen base names (one per line) and stop BEFORE
# provisioning anything. This is the CI matrix's source of truth — the discover
# job JSON-encodes this list, so the same default-exclusion + selector matching
# applies identically to a local run and to the parallel matrix.
if [ "$PRINT_SELECTED" = "1" ]; then
    for s in "${SELECTED[@]}"; do
        basename "$s" .sh
    done
    exit 0
fi

mkdir -p "$HARNESS_ROOT/tmp"

# The one rule for install/upgrade work (printed on every run by design):
# you cannot reason out whether these paths work — the only way to know is to
# run them for real, which is what you are doing now. Full reasoning + why these
# tests are special (they require commit→push→observe, unlike SQL/Go/integration
# tests you can run before pushing): doc/install-upgrade-testing.md.
echo ""
echo "── The only way to know if install/upgrade works is to run it. You are doing that now."
echo "   Why this is the only way (commit→push→build→run→observe→iterate): doc/install-upgrade-testing.md"

# Run each selected scenario, capturing per-run logs.
PASS_COUNT=0
FAIL_COUNT=0
FAILED_NAMES=()

for s in "${SELECTED[@]}"; do
    base=$(basename "$s" .sh)
    slug="$base"  # the canonical slug IS the filename, e.g. "3-postswap-worker-ddl-deadlock"
    vm_name="statbus-recovery-${base}"  # unique per scenario (one VM per scenario name)
    log_file="$HARNESS_ROOT/tmp/install-recovery-${base}.log"

    echo ""
    echo "═══════════════════════════════════════════════════════════════"
    echo "▶ Running scenario: $slug (VM=$vm_name)"
    echo "  Log: $log_file"
    echo "═══════════════════════════════════════════════════════════════"

    if bash "$s" "$vm_name" 2>&1 | tee "$log_file"; then
        PASS_COUNT=$((PASS_COUNT + 1))
        printf 'PASS  %s\n' "$slug"
    else
        FAIL_COUNT=$((FAIL_COUNT + 1))
        FAILED_NAMES+=("$slug")
        printf 'FAIL  %s\n' "$slug"
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
