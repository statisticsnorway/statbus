#!/bin/bash
# STATBUS-419 AC10: a fresh install never deletes files it did not create.
#
# An uninstall that kept the database backups left them in ~/statbus/dbdumps
# (the layout before kept backups moved out of the checkout). The fresh-install
# clone used to remove any ~/statbus without .git, backups included (since
# v2026.09.0). The install now sets kept backups aside in ~/statbus.dbdumps,
# where the Go installer moves them back after the clone, and refuses to touch
# any other file it finds there.
#
# Uses install.sh's STATBUS_INSTALL_TEST_GIT_CLONE seam, which runs the real
# statbus_git_clone against a git double that behaves like git clone: it
# refuses a non-empty destination and creates the destination with .git.
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
INSTALLER="${STATBUS_INSTALL_SCRIPT:-$REPO_ROOT/install.sh}"
tmpdir=$(mktemp -d)
trap 'rm -rf "$tmpdir"' EXIT
fail=0

mkdir -p "$tmpdir/bin"
cat > "$tmpdir/bin/git" <<'FAKE_GIT'
#!/bin/bash
[ "${1:-}" = clone ] || { echo "unexpected git invocation: $*" >&2; exit 65; }
destination="${!#}"
count=0
[ -f "$CLONE_COUNT" ] && count=$(cat "$CLONE_COUNT")
count=$((count + 1))
echo "$count" > "$CLONE_COUNT"
if [ -e "$destination" ] && [ -n "$(ls -A "$destination" 2>/dev/null)" ]; then
    echo "fatal: destination path '$destination' already exists and is not an empty directory." >&2
    exit 128
fi
created=0
[ -e "$destination" ] || created=1
mkdir -p "$destination/.git" "$destination/dbdumps"
: > "$destination/dbdumps/.gitkeep"
if [ "$count" -le "${CLONE_FAILURES:-0}" ]; then
    # Like git clone: a failed clone removes what it created.
    if [ "$created" = 1 ]; then rm -rf "$destination"; else rm -rf "$destination"/* "$destination"/.git; fi
    echo "fatal: early EOF" >&2
    exit 128
fi
echo "clone" > "$destination/README.md"
FAKE_GIT
for command_name in docker curl; do
    printf '#!/bin/bash\nexit 0\n' > "$tmpdir/bin/$command_name"
done
chmod +x "$tmpdir/bin/"*

run_clone() { # case-name -> rc, out
    export HOME="$tmpdir/$1"
    export CLONE_COUNT="$HOME/clone.count"
    out="$(PATH="$tmpdir/bin:$PATH" GIT_NETWORK_RETRY_DELAY_S=0 STATBUS_INSTALL_TEST_GIT_CLONE=1 bash "$INSTALLER" 2>&1)"
    rc=$?
}

# 1. Kept backups in the old place survive, set aside for the Go installer.
mkdir -p "$tmpdir/kept/statbus/dbdumps"
printf 'dump-bytes' > "$tmpdir/kept/statbus/dbdumps/un_20261105_121219.pg_dump"
: > "$tmpdir/kept/statbus/dbdumps/.gitkeep"
run_clone kept
if [ "$rc" -eq 0 ] && [ -d "$HOME/statbus/.git" ] \
    && [ "$(cat "$HOME/statbus.dbdumps/un_20261105_121219.pg_dump" 2>/dev/null)" = dump-bytes ]; then
    echo "PASS kept backups in ~/statbus/dbdumps are set aside in ~/statbus.dbdumps and the clone succeeds"
else
    echo "FAIL kept backups (rc=$rc):"; echo "$out"; ls -laR "$HOME" 2>&1 | head -30; fail=1
fi
grep -Fq "Kept backups from the earlier installation: moved $HOME/statbus/dbdumps to $HOME/statbus.dbdumps" <<<"$out" \
    || { echo "FAIL the move of the kept backups is not reported:"; echo "$out"; fail=1; }

# 2. A file the install did not create is never removed; the install says what
#    it found and stops.
mkdir -p "$tmpdir/foreign/statbus"
printf 'mine' > "$tmpdir/foreign/statbus/notes.txt"
run_clone foreign
if [ "$rc" -ne 0 ] && [ "$(cat "$HOME/statbus/notes.txt" 2>/dev/null)" = mine ] \
    && grep -Fq "$HOME/statbus is not a StatBus installation and holds: notes.txt" <<<"$out"; then
    echo "PASS a foreign file in ~/statbus is kept and named, and the install stops"
else
    echo "FAIL foreign file (rc=$rc):"; echo "$out"; fail=1
fi

# 3. A clone attempt that fails part-way is retried from a clean start, and
#    leaves nothing behind but the finished clone.
mkdir -p "$tmpdir/retry"
CLONE_FAILURES=1 run_clone retry
# .statbus-uninstall.lock is install.sh's own install/uninstall mutex.
leftovers=$(cd "$HOME" && ls -A | grep -v -e '^statbus$' -e '^clone.count$' -e '^.statbus-uninstall.lock$')
if [ "$rc" -eq 0 ] && [ "$(cat "$HOME/statbus/README.md" 2>/dev/null)" = clone ] && [ -z "$leftovers" ] \
    && [ "$(cat "$CLONE_COUNT")" = 2 ]; then
    echo "PASS a failed clone attempt is retried cleanly and leaves no partial copy"
else
    echo "FAIL retry (rc=$rc, attempts=$(cat "$CLONE_COUNT" 2>/dev/null), leftovers=$leftovers):"; echo "$out"; fail=1
fi

# 4. A kept backup never overwrites a different file of the same name.
mkdir -p "$tmpdir/clash/statbus/dbdumps" "$tmpdir/clash/statbus.dbdumps"
printf 'old' > "$tmpdir/clash/statbus/dbdumps/x.pg_dump"
printf 'other' > "$tmpdir/clash/statbus.dbdumps/x.pg_dump"
run_clone clash
if [ "$rc" -ne 0 ] && [ "$(cat "$HOME/statbus/dbdumps/x.pg_dump")" = old ] \
    && [ "$(cat "$HOME/statbus.dbdumps/x.pg_dump")" = other ]; then
    echo "PASS a kept backup is never overwritten by another of the same name"
else
    echo "FAIL clash (rc=$rc):"; echo "$out"; fail=1
fi

exit $fail
