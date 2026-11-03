#!/usr/bin/env bash
# A manual-box ssh session lasts hours, and the script may be edited (git pull,
# commit) while tmux is attached. When the session ends, the script finishes
# with the exit status of the session and runs nothing else from the edited
# file. Doubles: hcloud describes the labelled box; tmux reports the session as
# open and, during attach, rewrites the script the way a commit does.
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
work="$(mktemp -d "${TMPDIR:-/tmp}/manual-box-rewrite.XXXXXX")"
trap 'rm -rf "$work"' EXIT
mkdir -p "$work/ops" "$work/bin"
cp "$ROOT/ops/manual-box.sh" "$work/ops/"
echo 'HCLOUD_TOKEN=test-token-not-a-secret' > "$work/creds"

cat > "$work/bin/hcloud" <<'EOF'
#!/usr/bin/env bash
[ "$1 $2" = "server describe" ] || { echo "hcloud double: unexpected $*" >&2; exit 64; }
echo '{"labels":{"statbus-purpose":"manual-box"},"public_net":{"ipv4":{"ip":"192.0.2.1"}}}'
EOF
cat > "$work/bin/tmux" <<EOF
#!/usr/bin/env bash
case "\$1" in
has-session) exit 0 ;;
attach-session)
    # A commit while the session is open: text is inserted near the top.
    { head -n 3 "$work/ops/manual-box.sh"; printf '# edited during the session, shifting every later line by some bytes\n'; tail -n +4 "$work/ops/manual-box.sh"; } > "$work/next"
    cat "$work/next" > "$work/ops/manual-box.sh"
    echo "session ended"
    exit 0 ;;
*) echo "tmux double: unexpected \$*" >&2; exit 64 ;;
esac
EOF
chmod +x "$work/bin/hcloud" "$work/bin/tmux"

out="$(env -u TMUX PATH="$work/bin:$PATH" STATBUS_CREDENTIALS_FILE="$work/creds" bash "$work/ops/manual-box.sh" ssh statbus 2>&1)"
rc=$?
if [ "$rc" -eq 0 ] && [ "$out" = "session ended" ]; then
    echo "PASS the session ends cleanly after the script is edited"
    echo "manual-box rewrite test: PASS"
else
    echo "FAIL the session ends cleanly after the script is edited (exit $rc)"
    printf '%s\n' "$out" | sed 's/^/    /'
    echo "manual-box rewrite test: FAIL"
    exit 1
fi
