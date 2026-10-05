#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
INSTALL_SH_UNDER_TEST="${INSTALL_SH_UNDER_TEST:-$ROOT/install.sh}"
EXPECT_SCENARIO_A_REFUSAL="${EXPECT_SCENARIO_A_REFUSAL:-0}"
TMP_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/statbus-gapless-handoff.XXXXXX")
HOLDER_PID=""
trap 'if [ -n "$HOLDER_PID" ]; then kill "$HOLDER_PID" 2>/dev/null || true; wait "$HOLDER_PID" 2>/dev/null || true; fi; rm -rf "$TMP_ROOT"' EXIT

extract_lock_functions() {
    awk '
        /^STATBUS_REPO_LOCK_HELD=""/ { copy=1 }
        copy && $0 == "statbus_repo_lock_acquire" { exit }
        copy { print }
    ' "$INSTALL_SH_UNDER_TEST"
}

make_fixture() {
    local name="$1"
    FIXTURE="$TMP_ROOT/$name"
    export HOME="$FIXTURE/home"
    export STATBUS_DIR="$HOME/statbus"
    export STATBUS_INSTALL_RERUN_COMMAND="cd ~/statbus && ./sb install"
    mkdir -p "$STATBUS_DIR/.git" "$STATBUS_DIR/tmp" "$FIXTURE/bin"
    extract_lock_functions > "$FIXTURE/lock-functions.sh"
    cat > "$STATBUS_DIR/sb" <<'STUB'
#!/bin/bash
set -euo pipefail
flag="$PWD/tmp/upgrade-in-progress.json"
sleep "${STUB_PREFLIGHT_DELAY:-0}"
if [ -n "${STATBUS_INSTALL_MUTEX_FD:-}" ] && [ -n "${STATBUS_INSTALL_MUTEX_TOKEN:-}" ]; then
    perl -MJSON::PP -MFcntl=:flock -e '
        my ($path, $fd, $token) = @ARGV;
        open(my $held, "+<&=$fd") or exit 10;
        my @held = stat($held); my @path = stat($path);
        exit 11 unless @held && @path && $held[0] == $path[0] && $held[1] == $path[1];
        exit 12 unless flock($held, LOCK_EX|LOCK_NB);
        open(my $probe, "+<", $path) or exit 13;
        exit 14 if flock($probe, LOCK_EX|LOCK_NB);
        seek($held, 0, 0); local $/; my $raw = <$held>;
        my $flag = decode_json($raw);
        exit 15 unless ($flag->{holder} // "") eq "install";
        exit 16 unless ($flag->{handoff_token} // "") eq $token;
    ' "$flag" "$STATBUS_INSTALL_MUTEX_FD" "$STATBUS_INSTALL_MUTEX_TOKEN"
    printf 'inherited\n' >> "$RESULTS"
    exit 0
fi
perl -MFcntl=:flock -e '
    my ($path) = @ARGV; open(my $f, "+<", $path) or exit 2;
    exit(flock($f, LOCK_EX|LOCK_NB) ? 0 : 1);
' "$flag" && state=free || state=live
printf '%s\n' "$state" >> "$RESULTS"
[ "$state" = free ] && exit 0
printf 'An upgrade is already running. Wait for it to finish, then retry if needed.\n' >&2
exit 78
STUB
    chmod +x "$STATBUS_DIR/sb"
    export RESULTS="$FIXTURE/results"
    : > "$RESULTS"
}

run_lock_functions_and_stub() {
    # shellcheck disable=SC1090
    source "$FIXTURE/lock-functions.sh"
    statbus_repo_lock_acquire
    if declare -F statbus_repo_lock_prepare_handoff >/dev/null; then
        statbus_repo_lock_prepare_handoff
    else
        # origin/master behavior: release before ./sb install.
        statbus_repo_lock_release
    fi
    local rc=0
    (cd "$STATBUS_DIR" && ./sb install) || rc=$?
    statbus_repo_lock_release
    return "$rc"
}

start_demo_cadence_holder() {
    local flag="$STATBUS_DIR/tmp/upgrade-in-progress.json"
    perl -MTime::HiRes=sleep -MFcntl=:flock -e '
        my ($path) = @ARGV;
        for (1..20) {
            open(my $f, "+>>", $path) or die $!;
            flock($f, LOCK_EX) or die $!;
            seek($f, 0, 0); truncate($f, 0);
            print $f qq|{"holder":"service","trigger":"install-cli"}\n|;
            sleep 1.7;
            unlink($path) or die $!;
            flock($f, LOCK_UN); close($f);
            sleep 0.2;
        }
    ' "$flag" &
    HOLDER_PID=$!
}

scenario_a() {
    make_fixture scenario-a
    export STUB_PREFLIGHT_DELAY=0.25
    start_demo_cadence_holder
    sleep 0.1
    local rc=0
    run_lock_functions_and_stub || rc=$?
    kill "$HOLDER_PID" 2>/dev/null || true
    wait "$HOLDER_PID" 2>/dev/null || true
    HOLDER_PID=""
    if [ "$EXPECT_SCENARIO_A_REFUSAL" = 1 ]; then
        [ "$rc" -eq 78 ]
        grep -Fxq live "$RESULTS"
        echo "scenario A: reproduced pre-fix refusal"
    else
        [ "$rc" -eq 0 ]
        grep -Fxq inherited "$RESULTS"
        [ "$(wc -l < "$RESULTS" | tr -d ' ')" -eq 1 ]
        echo "scenario A: one install completed through inherited hold"
    fi
}

start_inverse_holder() {
    local flag="$STATBUS_DIR/tmp/upgrade-in-progress.json" marker="$FIXTURE/long-held" released="$FIXTURE/long-released"
    perl -MTime::HiRes=sleep -MFcntl=:flock -e '
        my ($path, $marker, $released) = @ARGV;
        for (1..6) {
            open(my $f, "+>>", $path) or die $!; flock($f, LOCK_EX) or die $!;
            seek($f, 0, 0); truncate($f, 0); print $f qq|{"holder":"service"}\n|;
            sleep 0.03; unlink($path) or die $!; flock($f, LOCK_UN); close($f); sleep 0.03;
        }
        open(my $f, "+>>", $path) or die $!; flock($f, LOCK_EX) or die $!;
        seek($f, 0, 0); truncate($f, 0); print $f qq|{"holder":"service","healthy":true}\n|;
        open(my $m, ">", $marker) or die $!; print $m "held\n"; close($m);
        sleep 12;
        unlink($path) or die $!; flock($f, LOCK_UN); close($f);
        open(my $r, ">", $released) or die $!; print $r "released\n"; close($r);
    ' "$flag" "$marker" "$released" &
    HOLDER_PID=$!
}

scenario_b() {
    make_fixture scenario-b
    export STUB_PREFLIGHT_DELAY=0
    start_inverse_holder
    for _ in $(seq 1 200); do [ -f "$FIXTURE/long-held" ] && break; sleep 0.02; done
    [ -f "$FIXTURE/long-held" ]
    local started ended rc=0
    started=$(date +%s)
    run_lock_functions_and_stub || rc=$?
    ended=$(date +%s)
    wait "$HOLDER_PID"
    HOLDER_PID=""
    [ "$rc" -eq 0 ]
    [ -f "$FIXTURE/long-released" ]
    [ $((ended - started)) -ge 11 ]
    grep -Fxq inherited "$RESULTS"
    echo "scenario B: installer waited for the 12-second healthy holder and then inherited the lock"
}

scenario_a
if [ "$EXPECT_SCENARIO_A_REFUSAL" != 1 ]; then
    scenario_b
fi
