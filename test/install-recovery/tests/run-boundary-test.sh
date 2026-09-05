#!/bin/bash
set -euo pipefail

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$TEST_DIR/../../.." && pwd)"
RUNNER="$REPO_ROOT/test/install-recovery/run.sh"

TMP_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/statbus-352-runner.XXXXXX")"
trap 'rm -rf "$TMP_ROOT"' EXIT

HARNESS_DIR="$TMP_ROOT/test/install-recovery"
SCENARIOS_DIR="$HARNESS_DIR/scenarios"
ARCS_DIR="$HARNESS_DIR/arcs"
FAKEBIN="$TMP_ROOT/fakebin"
TRACE_LOG="$TMP_ROOT/trace.log"
mkdir -p "$SCENARIOS_DIR" "$ARCS_DIR" "$FAKEBIN" "$TMP_ROOT/tmp"
cp "$RUNNER" "$HARNESS_DIR/run.sh"
chmod +x "$HARNESS_DIR/run.sh"

cat > "$SCENARIOS_DIR/scenario-a.sh" <<'EOF'
#!/bin/bash
set -euo pipefail
echo SCENARIO_A_EXECUTED
EOF
cat > "$SCENARIOS_DIR/scenario-b.sh" <<'EOF'
#!/bin/bash
set -euo pipefail
echo SCENARIO_B_EXECUTED
EOF
cat > "$SCENARIOS_DIR/3-postswap-green.sh" <<'EOF'
#!/bin/bash
set -euo pipefail
echo GREEN_EXECUTED
EOF
cat > "$SCENARIOS_DIR/3-postswap-known-red.sh" <<'EOF'
#!/bin/bash
# HARNESS_SKIP_DEFAULT: deliberate known-RED fixture
set -euo pipefail
echo KNOWN_RED_EXECUTED
EOF
cat > "$ARCS_DIR/working-arc.sh" <<'EOF'
#!/bin/bash
set -euo pipefail
echo ARC_EXECUTED
EOF
chmod +x "$SCENARIOS_DIR"/*.sh "$ARCS_DIR"/*.sh

REAL_GREP="$(command -v grep)"
REAL_FIND="$(command -v find)"
REAL_GIT="$(command -v git)"
export REAL_GREP REAL_FIND REAL_GIT

cat > "$FAKEBIN/grep" <<'EOF'
#!/bin/bash
printf 'grep' >> "${TRACE_LOG:?}"
printf ' <%s>' "$@" >> "$TRACE_LOG"
printf '\n' >> "$TRACE_LOG"
if [ "${FORBID_DOMAIN_READS:-0}" = "1" ]; then
    case " $* " in
        *scenario-b.sh*) echo "FORBIDDEN sibling grep: $*" >&2; exit 97 ;;
    esac
fi
exec "$REAL_GREP" "$@"
EOF

cat > "$FAKEBIN/find" <<'EOF'
#!/bin/bash
printf 'find' >> "${TRACE_LOG:?}"
printf ' <%s>' "$@" >> "$TRACE_LOG"
printf '\n' >> "$TRACE_LOG"
if [ "${FORBID_DOMAIN_READS:-0}" = "1" ]; then
    case " $* " in
        *'/scenarios '*|*'/arcs '*) echo "FORBIDDEN domain enumeration: $*" >&2; exit 98 ;;
    esac
fi
exec "$REAL_FIND" "$@"
EOF

cat > "$FAKEBIN/bash" <<'EOF'
#!/bin/bash
printf 'bash' >> "${TRACE_LOG:?}"
printf ' <%s>' "$@" >> "$TRACE_LOG"
printf '\n' >> "$TRACE_LOG"
if [ "${FORBID_DOMAIN_READS:-0}" = "1" ]; then
    case " $* " in
        *scenario-b.sh*) echo "FORBIDDEN sibling execution: $*" >&2; exit 99 ;;
    esac
fi
exec /bin/bash "$@"
EOF

cat > "$FAKEBIN/git" <<'EOF'
#!/bin/bash
printf 'git' >> "${TRACE_LOG:?}"
printf ' <%s>' "$@" >> "$TRACE_LOG"
printf '\n' >> "$TRACE_LOG"
case " $* " in
    *' rev-parse HEAD '*) echo 0123456789abcdef0123456789abcdef01234567; exit 0 ;;
    *' branch -r --contains '*) echo '  origin/master'; exit 0 ;;
esac
exec "$REAL_GIT" "$@"
EOF
chmod +x "$FAKEBIN"/*

RUN_RC=0
RUN_OUT=""
RUN_ERR=""
run_runner() {
    local name="$1" forbid="$2"
    shift 2
    : > "$TRACE_LOG"
    set +e
    FORBID_DOMAIN_READS="$forbid" TRACE_LOG="$TRACE_LOG" PATH="$FAKEBIN:$PATH" \
        /bin/bash "$HARNESS_DIR/run.sh" "$@" \
        > "$TMP_ROOT/$name.out" 2> "$TMP_ROOT/$name.err"
    RUN_RC=$?
    set -e
    RUN_OUT="$(cat "$TMP_ROOT/$name.out")"
    RUN_ERR="$(cat "$TMP_ROOT/$name.err")"
}

fail() {
    echo "FAIL: $*" >&2
    exit 1
}

assert_rc() {
    local want="$1" name="$2"
    [ "$RUN_RC" -eq "$want" ] || fail "$name: wanted exit $want, got $RUN_RC\nstdout:\n$RUN_OUT\nstderr:\n$RUN_ERR"
    echo "PASS: $name (exit $RUN_RC)"
}

assert_stdout_eq() {
    local want="$1" name="$2"
    [ "$RUN_OUT" = "$want" ] || fail "$name: unexpected stdout\nwant:\n$want\ngot:\n$RUN_OUT"
    echo "PASS: $name output"
}

assert_contains() {
    local haystack="$1" needle="$2" name="$3"
    case "$haystack" in
        *"$needle"*) ;;
        *) fail "$name: missing '$needle' in:\n$haystack" ;;
    esac
    echo "PASS: $name"
}

# Authoritative non-exact discovery must still scan every sibling and reject a
# forbidden construct before it can emit a paid matrix.
cat > "$SCENARIOS_DIR/scenario-b.sh" <<'EOF'
#!/bin/bash
fabricate_sibling_state "must be rejected by discovery"
EOF
run_runner forbidden-sibling 0 --print-selected scenario-a
assert_rc 1 "forbidden sibling blocks discovery"
assert_contains "$RUN_ERR" "FABRICATION" "forbidden sibling diagnostic"
assert_contains "$RUN_ERR" "REFUSING: 1 fabrication/ledger-write violation" "forbidden sibling refusal"

cat > "$SCENARIOS_DIR/scenario-b.sh" <<'EOF'
#!/bin/bash
set -euo pipefail
echo SCENARIO_B_EXECUTED
EOF
chmod +x "$SCENARIOS_DIR/scenario-b.sh"

# Existing selector semantics remain authoritative: full excludes known-RED,
# exact/fragment can name it, phase-prefix does not, and duplicates collapse.
run_runner full-selection 0 --print-selected
assert_rc 0 "full selection"
assert_stdout_eq $'3-postswap-green\nscenario-a\nscenario-b' "full selection excludes known-RED"

run_runner known-red-exact 0 --print-selected 3-postswap-known-red
assert_rc 0 "known-RED exact selection"
assert_stdout_eq "3-postswap-known-red" "known-RED exact selection"

run_runner known-red-phase 0 --print-selected 3-postswap
assert_rc 0 "known-RED phase selection"
assert_stdout_eq "3-postswap-green" "phase selection excludes known-RED"

run_runner duplicate-selection 0 --print-selected scenario-a scenario-a
assert_rc 0 "duplicate selection"
assert_stdout_eq "scenario-a" "duplicate selection is deduplicated"

# Exact mode is a one-slug execution boundary. A forbidden sibling is left in
# place while expected content-reader commands fail if they enumerate or read it.
cat > "$SCENARIOS_DIR/scenario-b.sh" <<'EOF'
#!/bin/bash
fabricate_sibling_state "exact execution must not read this sibling"
EOF
rm -f "$TMP_ROOT/tmp/install-recovery-test-passed-sha"
run_runner exact-safe 1 --exact scenario-a
assert_rc 0 "safe exact execution"
assert_contains "$RUN_OUT" "SCENARIO_A_EXECUTED" "safe exact executes selected scenario"
[ ! -e "$TMP_ROOT/tmp/install-recovery-test-passed-sha" ] || fail "exact execution wrote the full-suite stamp"
if "$REAL_GREP" -q 'find .*\/scenarios\|find .*\/arcs\|scenario-b\.sh' "$TRACE_LOG"; then
    fail "exact execution enumerated/read a sibling domain:\n$(cat "$TRACE_LOG")"
fi
assert_contains "$(cat "$TRACE_LOG")" "bash <$SCENARIOS_DIR/scenario-a.sh>" "exact execution joins the shared execution loop"
echo "PASS: exact execution neither reads siblings nor writes the full-suite stamp"

run_runner exact-missing 0 --exact missing-scenario
assert_rc 2 "missing exact scenario"
assert_contains "$RUN_ERR" "does not exist" "missing exact scenario diagnostic"

for unsafe in '' '../scenario-a' '/absolute' '.hidden' 'two words' '*' '--option'; do
    name="unsafe-$(printf '%s' "$unsafe" | tr -c 'A-Za-z0-9' '_' )"
    run_runner "$name" 0 --exact "$unsafe"
    assert_rc 2 "unsafe exact slug '$unsafe'"
done

ln -s scenario-a.sh "$SCENARIOS_DIR/scenario-link.sh"
run_runner exact-symlink 0 --exact scenario-link
assert_rc 2 "exact symlink refusal"
assert_contains "$RUN_ERR" "regular non-symlink" "exact symlink diagnostic"

run_runner mixed-selector 0 --exact scenario-a scenario-b
assert_rc 2 "exact plus positional selector"
run_runner mixed-list 0 --exact scenario-a --list
assert_rc 2 "exact plus list"
run_runner mixed-print 0 --exact scenario-a --print-selected
assert_rc 2 "exact plus print-selected"
run_runner mixed-keep 0 --keep-vm --exact scenario-a
assert_rc 2 "exact plus keep-vm"
run_runner mixed-exact 0 --exact scenario-a --exact scenario-b
assert_rc 2 "duplicate exact flag"
run_runner missing-exact-value 0 --exact
assert_rc 2 "missing exact value"

echo "install-recovery runner boundary tests: PASS"
