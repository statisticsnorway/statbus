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
#   ./dev.sh test-install-recovery --exact 0-happy-install  # one discovery-emitted slug
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

# ─────────────────────────────────────────────────────────────────────────
# STATBUS-071 P6 — the structural guard: no fabrication, ever again.
#
# The whole framework (STATBUS-071) exists to prove upgrade/recovery against
# REAL machinery, not hand-built rows. By P5 every scenario/arc that used to
# fabricate a crash state directly (fabricate_scheduled_upgrade_row,
# fabricate_resume_state — both deleted at zero callers) was reshaped onto the
# real register+schedule+dispatch path. This check is what keeps it that way:
# it fails loudly if a future "just this once" convenience fabrication tries
# to land, so the doctrine is self-enforcing instead of tribal memory.
#
# Two forbidden shapes, scanned across every *.sh under scenarios/ and arcs/:
#   (a) a CALL-shaped `fabricate_*` reference — a line that (after leading
#       whitespace) BEGINS with `fabricate_<name>` followed by a space or `(`.
#       This catches both a call (`fabricate_foo "$VM_NAME" ...`) and a bare
#       function definition (`fabricate_foo() {`) landing directly in a
#       scenario/arc file. It does NOT catch prose — a comment (`# ... uses
#       fabricate_foo ...`) or an echo/PASS string quoting the name never
#       starts the line with the identifier itself, so historical/supersession
#       notes (which must stay, per STATBUS-071 P3/P5) never trip it.
#   (b) a ledger-write pattern (`INSERT INTO public.upgrade` / `UPDATE
#       public.upgrade`) anywhere in the file. Writes to the ledger belong to
#       the PRODUCT only — a scenario/arc proves behavior by driving the real
#       machinery and reading the result, never by hand-writing the row the
#       machinery is supposed to produce. The ONE sanctioned exception is a
#       GUARD-PROBE that deliberately attempts a forbidden write to prove a DB
#       trigger REFUSES it (c-rollback-resurrection-arc.sh's terminal-
#       resurrection probe, STATBUS-160) — such a line must carry the literal
#       marker below on the SAME line, naming itself as sanctioned and why.
#
# Runs for every authoritative non-exact invocation (a broad/local scenario
# run, --list, --print-selected). The explicit --exact mode is intentionally
# downstream of a successful same-commit discovery job, so it validates and
# executes one already-emitted scenario without re-reading sibling contents.
LEDGER_WRITE_SANCTION_MARKER="HARNESS-SANCTIONED-LEDGER-WRITE"

check_no_fabrication_or_ledger_writes() {
    local scan_dir file line violations=0
    for scan_dir in "$@"; do
        [ -d "$scan_dir" ] || continue
        while IFS= read -r file; do
            while IFS= read -r line; do
                local lineno content
                lineno="${line%%:*}"
                content="${line#*:}"
                echo "✗ FABRICATION: $file:$lineno matches a call-shaped 'fabricate_*' reference:" >&2
                echo "    $content" >&2
                echo "    Doctrine (STATBUS-071 P6, no-fabrication): scenarios/arcs must drive the" >&2
                echo "    real register+schedule+dispatch path, never hand-construct crash state." >&2
                violations=$((violations + 1))
            done < <(grep -nE '^[[:space:]]*fabricate_[A-Za-z0-9_]+[[:space:](]' "$file" || true)

            while IFS= read -r line; do
                local lineno content
                lineno="${line%%:*}"
                content="${line#*:}"
                if [[ "$content" == *"$LEDGER_WRITE_SANCTION_MARKER"* ]]; then
                    continue
                fi
                echo "✗ LEDGER WRITE: $file:$lineno writes public.upgrade directly:" >&2
                echo "    $content" >&2
                echo "    Doctrine (STATBUS-071 P6, no-fabrication): writes to the ledger belong to" >&2
                echo "    the PRODUCT only. If this is a deliberate GUARD-PROBE proving a DB trigger" >&2
                echo "    REFUSES the write (STATBUS-160 genre), mark the SAME line with the literal" >&2
                echo "    string ${LEDGER_WRITE_SANCTION_MARKER} and name the doctrine it proves." >&2
                violations=$((violations + 1))
            done < <(grep -nE 'INSERT INTO public\.upgrade|UPDATE public\.upgrade' "$file" || true)
        done < <(find "$scan_dir" -maxdepth 1 -name '*.sh' -type f | sort)
    done
    if [ "$violations" -gt 0 ]; then
        echo "" >&2
        echo "════════════════════════════════════════════════════════════════" >&2
        echo "  REFUSING: $violations fabrication/ledger-write violation(s) found (STATBUS-071 P6)." >&2
        echo "  The harness proves upgrade/recovery against REAL machinery — see the header" >&2
        echo "  of this check in run.sh for the doctrine and the sanctioned-exception marker." >&2
        echo "════════════════════════════════════════════════════════════════" >&2
        return 1
    fi
    return 0
}

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
EXACT_MODE=0
EXACT_SLUG=""
SELECTORS=()
while [ $# -gt 0 ]; do
    case "$1" in
        --keep-vm) KEEP_VM=1 ;;
        --list)    LIST_ONLY=1 ;;
        --print-selected) PRINT_SELECTED=1 ;;
        --exact)
            if [ "$EXACT_MODE" = "1" ]; then
                echo "--exact may be specified only once" >&2
                exit 2
            fi
            if [ $# -lt 2 ]; then
                echo "--exact requires one discovery-emitted scenario slug" >&2
                exit 2
            fi
            EXACT_MODE=1
            EXACT_SLUG="$2"
            shift
            ;;
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
  --exact SLUG       Execute exactly one safe slug emitted by a successful
                     same-commit --print-selected discovery. Does not enumerate
                     or inspect sibling scenarios. Cannot be mixed with selectors,
                     --list, --print-selected, or --keep-vm.
  --keep-vm          Leave VMs running on failure (debug)
  --help, -h         This message

Examples:
  ./dev.sh test-install-recovery                  # all scenarios
  ./dev.sh test-install-recovery --list           # see what's available
  ./dev.sh test-install-recovery 0-happy 3-postswap            # the happy baselines + every post-swap scenario
  ./dev.sh test-install-recovery worker-busy      # by name substring
  ./dev.sh test-install-recovery --exact 0-happy-install       # CI matrix execution only
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

SELECTED=()
if [ "$EXACT_MODE" = "1" ]; then
    if [ "$LIST_ONLY" = "1" ] || [ "$PRINT_SELECTED" = "1" ] || [ "$KEEP_VM" = "1" ] || [ ${#SELECTORS[@]} -ne 0 ]; then
        echo "--exact cannot be combined with selectors, --list, --print-selected, or --keep-vm" >&2
        exit 2
    fi
    if [[ ! "$EXACT_SLUG" =~ ^[A-Za-z0-9][A-Za-z0-9_-]*$ ]]; then
        echo "Unsafe exact scenario slug: '$EXACT_SLUG'" >&2
        echo "Expected a discovery-emitted basename containing only letters, digits, '_' or '-'." >&2
        exit 2
    fi
    exact_path="$SCENARIOS_DIR/${EXACT_SLUG}.sh"
    if [ -L "$exact_path" ]; then
        echo "Exact scenario must be a regular non-symlink file: $exact_path" >&2
        exit 2
    fi
    if [ ! -f "$exact_path" ]; then
        echo "Exact scenario does not exist: $exact_path" >&2
        exit 2
    fi
    SELECTED=("$exact_path")
else
    check_no_fabrication_or_ledger_writes "$SCENARIOS_DIR" "$HARNESS_DIR/arcs"

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
fi

mkdir -p "$HARNESS_ROOT/tmp"

# ── STATBUS-132: fail fast if the sb build commit is not on origin ──────────────
# dev.sh rebuilds ./sb embedding `git rev-parse HEAD`; the VM's clone has ONLY
# origin. If HEAD is a LOCAL commit (Backlog.md board edits create one on every
# ticket edit, so HEAD routinely sits ahead of origin between code pushes), the
# uploaded sb's embedded commit is unresolvable on the VM and the VM-side
# freshness check dies late with "fatal: bad object" — AFTER provisioning +
# bootstrap + install, i.e. a paid Hetzner VM + ~10 min to discover something
# knowable here in milliseconds. Refuse BEFORE the first VM. Runs only on an
# actual run (after --list / --print-selected have exited above).
preflight_head_on_origin() {
    local sha
    sha="$(git -C "$HARNESS_ROOT" rev-parse HEAD 2>/dev/null)" || {
        echo "WARN: could not resolve HEAD (git rev-parse) — skipping the origin preflight" >&2
        return 0
    }
    # Fast path (no network): an ORIGIN remote-tracking branch already contains
    # it. Filtered to origin/ — a fork remote containing HEAD must not pass,
    # since origin is what the VM clones (reviewer tightening).
    if git -C "$HARNESS_ROOT" branch -r --contains "$sha" 2>/dev/null | grep -q '^ *origin/'; then
        return 0
    fi
    # Slow path: ask origin directly — local remote-tracking refs may be stale, or
    # a CI checkout may lack them. GIT_TERMINAL_PROMPT=0 so a missing credential
    # fails fast instead of hanging on a prompt. HEAD present as a ref tip ⇒ pushed.
    local remote_refs
    if remote_refs="$(GIT_TERMINAL_PROMPT=0 git -C "$HARNESS_ROOT" ls-remote origin 2>/dev/null)"; then
        if printf '%s\n' "$remote_refs" | grep -q "^${sha}[[:space:]]"; then
            return 0
        fi
    else
        echo "WARN: could not reach origin (git ls-remote) to verify HEAD is pushed —" >&2
        echo "      proceeding; a genuinely-unpushed commit will still fail VM-side as before." >&2
        return 0
    fi
    # origin reachable, HEAD neither contained by a remote branch nor a ref tip → not pushed.
    echo "" >&2
    echo "════════════════════════════════════════════════════════════════" >&2
    echo "  REFUSING: HEAD ($sha) is not on origin — the VM cannot resolve it." >&2
    echo "════════════════════════════════════════════════════════════════" >&2
    echo "  The harness builds ./sb from HEAD and uploads it; the VM's clone has only" >&2
    echo "  origin, so an unpushed HEAD dies VM-side with 'fatal: bad object' AFTER" >&2
    echo "  burning a paid VM + ~10 min. Push first (board edits create a local commit" >&2
    echo "  on every ticket edit — mind the freeze discipline), then re-run:" >&2
    echo "      git push" >&2
    echo "  If you DID just push, refresh remote-tracking and re-run:" >&2
    echo "      git -C \"$HARNESS_ROOT\" fetch origin" >&2
    echo "════════════════════════════════════════════════════════════════" >&2
    exit 3
}
preflight_head_on_origin

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
if [ "$EXACT_MODE" = "0" ] && [ ${#SELECTORS[@]} -eq 0 ]; then
    git -C "$HARNESS_ROOT" rev-parse HEAD > "$STAMP_FILE"
    echo "Stamp recorded (install-recovery-test-passed-sha): $(cat "$STAMP_FILE")"
fi

echo "All scenarios passed."
