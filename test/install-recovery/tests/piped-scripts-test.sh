#!/usr/bin/env bash
# STATBUS-571: operators run every script as curl -fsSL <url> | bash. Piped,
# each script must
#   1. run: setup reaches main (its --help prints the usage), install parses
#      its arguments, uninstall asks its questions on the terminal and acts on
#      the answers typed there (not on the rest of the script in the pipe);
#   2. run nothing when the download is cut short: bash exits 2 with no
#      output from the script, at every cut point tried;
#   3. setup without a terminal and without --non-interactive refuses, naming
#      --non-interactive, instead of reading answers from the pipe.
# The scripts are the real ones from this checkout; a pty stands in for the
# operator's terminal. HOME is a scratch directory, so nothing on this machine
# is touched.
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
work="$(mktemp -d "${TMPDIR:-/tmp}/piped-scripts.XXXXXX")"
trap 'rm -rf "$work"' EXIT
fail=0
pass() { echo "PASS $1"; }
nope() { echo "FAIL $1"; fail=1; }

# pty_pipe <script> <answers> [args...]: run `cat script | bash -s -- args` in
# a new session whose controlling terminal is a pty; the answers are typed on
# that terminal. Prints everything the terminal showed.
cat > "$work/pty_pipe.py" <<'EOF'
import os, pty, select, signal, sys, time
script, answers, home = sys.argv[1], sys.argv[2].encode(), sys.argv[3]
args = sys.argv[4:]
pid, fd = pty.fork()
if pid == 0:
    env = dict(os.environ, HOME=home)
    env.pop("STATBUS_UNINSTALL_CONFIRM", None)
    quoted = " ".join("'" + a.replace("'", "'\\''") + "'" for a in args)
    os.execvpe("bash", ["bash", "-c", f"cat '{script}' | bash -s -- {quoted}"], env)
out = b""
sent = False
deadline = time.time() + 60
while True:
    if time.time() > deadline:
        os.kill(pid, signal.SIGKILL)
        out += b"\n[pty_pipe: still running after 60s; killed]\n"
        break
    ready, _, _ = select.select([fd], [], [], 0.5)
    if not ready:
        continue
    try:
        data = os.read(fd, 4096)
    except OSError:
        break
    if not data:
        break
    out += data
    if not sent and b"?" in out:
        os.write(fd, answers)
        sent = True
_, status = os.waitpid(pid, 0)
sys.stdout.buffer.write(out.replace(b"\r\n", b"\n"))
sys.exit(os.waitstatus_to_exitcode(status))
EOF
pty_pipe() { local script=$1 answers=$2; shift 2; python3 "$work/pty_pipe.py" "$script" "$answers" "$work/home" "$@"; }
mkdir -p "$work/home"

# 1. Piped runs.
out=$(pty_pipe "$ROOT/ops/setup-ubuntu-lts.sh" "" --help 2>&1)
if grep -q -- '--non-interactive' <<<"$out" && grep -q 'Stages, in run order:' <<<"$out"; then
    pass "piped setup reaches main (--help prints the usage)"
else
    nope "piped setup reaches main (--help prints the usage)"; printf '    %s\n' "$out" | tail -5
fi

out=$(pty_pipe "$ROOT/install.sh" "" --bogus 2>&1); rc=$?
if [ "$rc" = 1 ] && grep -qx 'Unknown option: --bogus' <<<"$out"; then
    pass "piped install parses its arguments"
else
    nope "piped install parses its arguments (exit $rc)"; printf '    %s\n' "$out" | tail -5
fi

# Uninstall with nothing installed: three keep/delete answers and the DELETE
# confirmation, then it finishes. The answers come from the terminal; the rest
# of the script stays in the pipe.
out=$(pty_pipe "$ROOT/uninstall.sh" $'n\nn\ny\nDELETE\n' 2>&1); rc=$?
if [ "$rc" = 0 ] && grep -q 'Keep the users?' <<<"$out" && grep -q 'Removal complete' <<<"$out"; then
    pass "piped uninstall asks on the terminal and finishes"
else
    nope "piped uninstall asks on the terminal and finishes (exit $rc)"; printf '    %s\n' "$out" | tail -5
fi

# 2. A download cut short runs nothing, wherever it is cut.
for script in ops/setup-ubuntu-lts.sh install.sh uninstall.sh; do
    lines=$(wc -l < "$ROOT/$script")
    ran=""
    for cut in 15 40 120 $((lines / 4)) $((lines / 2)) $((lines * 3 / 4)) $((lines - 3)); do
        head -n "$cut" "$ROOT/$script" > "$work/cut.sh"
        # LC_ALL=C: bash's own parse error is recognised by its English text.
        out=$(cd "$work/home" && HOME="$work/home" LC_ALL=C bash < "$work/cut.sh" 2>&1); rc=$?
        if [ "$rc" != 2 ] || grep -v 'syntax error\|unexpected end of file\|^bash: line' <<<"$out" | grep -q .; then
            ran="$ran $cut(exit $rc)"
        fi
    done
    if [ -z "$ran" ]; then
        pass "$script cut short runs nothing"
    else
        nope "$script cut short runs nothing; ran at line:$ran"
    fi
done

# 3. Setup piped without a terminal and without --non-interactive refuses.
# A new session with no controlling terminal (python's os.setsid; setsid(1) is
# not on macOS), as under cron, ssh without -t or a CI runner.
out=$(cd "$work/home" && HOME="$work/home" python3 -c '
import os, sys
os.setsid()
os.execvp("bash", ["bash", "-c", sys.argv[1]])
' "cat '$ROOT/ops/setup-ubuntu-lts.sh' | bash" </dev/null 2>&1); rc=$?
if [ "$rc" != 0 ] && grep -q -- '--non-interactive' <<<"$out" && ! grep -q 'Stages in this run' <<<"$out"; then
    pass "setup with no terminal refuses and names --non-interactive"
else
    nope "setup with no terminal refuses and names --non-interactive (exit $rc)"; printf '    %s\n' "$out" | tail -5
fi

if [ "$fail" = 0 ]; then echo "piped scripts test: PASS"; else echo "piped scripts test: FAIL"; exit 1; fi
