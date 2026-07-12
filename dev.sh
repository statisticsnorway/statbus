#!/bin/bash
# dev.sh — Development-only commands for StatBus
#
# These commands are for local development and are NOT available in production.
# For production/ops commands, use ./sb (the Go CLI).
#
# Usage: ./dev.sh <command> [args...]
#
set -euo pipefail

if [ "${DEBUG:-}" = "true" ] || [ "${DEBUG:-}" = "1" ]; then
  set -x
fi

# Ensure Homebrew tools (Go, etc.) are in PATH on servers
if [ -f /home/linuxbrew/.linuxbrew/bin/brew ]; then
  eval "$(/home/linuxbrew/.linuxbrew/bin/brew shellenv)"
fi

WORKSPACE="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
cd "$WORKSPACE"

# Activate repo git hooks. `.githooks/pre-push` blocks hand-rolled release
# tags and guards the postgres/Dockerfile pgrx-builder stages. A fresh
# clone has core.hooksPath unset (defaults to .git/hooks, which is empty
# here), so the guards silently wouldn't run until a developer manually
# ran the config. Setting it on every dev.sh invocation is idempotent and
# ensures the guards are live for anyone who uses dev.sh at all.
if [ "$(git config core.hooksPath 2>/dev/null || true)" != ".githooks" ]; then
    git config core.hooksPath .githooks
fi

# Rebuild ./sb when EITHER drift axis fires — they need different evidence,
# and neither tool can see the other's axis:
#   - the binary doesn't exist, OR
#   - HOT-EDIT axis: any cli/**/*.go is newer than the binary (local WIP edit).
#     Only a file mtime catches this — git can't tell whether the binary was
#     built from the current *uncommitted* bytes. Self-clears on rebuild.
#   - COMMITTED axis: the binary's build commit differs from HEAD with cli/
#     changes between. `git commit`/`checkout`/`pull` move HEAD WITHOUT touching
#     working-tree mtimes, so the mtime check above is blind to it. `./sb
#     committed-drift` answers from the binary's baked-in build commit vs live
#     HEAD (reliable even when the binary is stale) and exits non-zero on drift
#     (or if it cannot confirm freshness). It is guard-exempt, so it never warns
#     into this check.
sb_needs_rebuild=false
if ! test -x ./sb; then
    sb_needs_rebuild=true
elif [ -n "$(find cli -name '*.go' -newer ./sb -print -quit 2>/dev/null)" ]; then
    sb_needs_rebuild=true
elif ! ./sb committed-drift; then
    sb_needs_rebuild=true
fi
if [ "$sb_needs_rebuild" = true ]; then
    if command -v go >/dev/null 2>&1; then
        echo "Building sb from source..."
        # Inject version from git describe verbatim — it carries the leading "v"
        # (the canonical CommitVersion form stored in public.upgrade.commit_version
        # and printed by ./sb --version). No strip/re-prepend dance (STATBUS-064).
        # --match 'v[0-9]*' restricts git describe to release tags. The moving
        # install-verified tag was deleted in rc.62; this filter remains as
        # defense against any stray non-release tags landing in the refs/tags/ space.
        _SB_VERSION=$(git describe --tags --always --match 'v[0-9]*' 2>/dev/null || echo "dev")
        # Full 40-char commit_sha for cmd.commit ldflag — equality-compared
        # against public.upgrade.commit_sha in the upgrade service's
        # ground-truth check. Display-only trimming happens via
        # upgrade.ShortForDisplay() / commitShort() in Go (rc.63 canonical).
        _SB_COMMIT=$(git rev-parse HEAD 2>/dev/null || echo "unknown")
        _SB_LDFLAGS="-X 'github.com/statisticsnorway/statbus/cli/cmd.version=${_SB_VERSION}' -X 'github.com/statisticsnorway/statbus/cli/cmd.commit=${_SB_COMMIT}'"
        (cd cli && go build -ldflags "$_SB_LDFLAGS" -o ../sb .)
    else
        echo "Error: ./sb binary not found or out of date. Build it with: cd cli && go build -o ../sb ."
        exit 1
    fi
fi

# Auto-fetch DB seed if not cached locally.
# Intent: speeds up create-db from ~294 migrations to one pg_restore (~2 seconds).
# Uses ./sb db seed fetch — one implementation in Go, shared by dev.sh and ./sb install.
# Placed AFTER the rebuild block so the current binary is always used.
#
# NON-FATAL: the seed is a pure speed optimization. `./sb db seed fetch` exits 1
# ("manifest unknown") when the published statbus-seed:<commit_short> image does
# not exist for this commit — a freshly-pushed commit whose Images run hasn't
# built the seed yet, or any non-master ref Images never builds at all. Under
# `set -e` an unguarded failure here aborts the WHOLE ./dev.sh invocation; that
# killed the install-recovery harness's `build-sb` discover step on a fresh
# commit (STATBUS-025 — the build phase died before any scenario ran). Mirror
# install.go's runSeedRestore: warn and proceed; create-db just replays all
# migrations instead of restoring the seed.
if [ ! -f "$WORKSPACE/.db-seed/seed.pg_dump" ] && [ -x ./sb ]; then
    ./sb db seed fetch || echo "Note: no seed image for this commit — proceeding without the seed cache (create-db will replay all migrations)."
fi

# Set TTY_INPUT to /dev/tty if available (interactive), otherwise /dev/null
if [ -e /dev/tty ]; then
  export TTY_INPUT=/dev/tty
else
  export TTY_INPUT=/dev/null
fi

# ---- Tier-1 stamp guard ----
#
# Used by `./dev.sh test fast`, `./dev.sh generate-doc-db`, and
# (via a parallel Go implementation in cli/cmd/types.go) `./sb types generate`.
# Three outcomes, each printed verbatim to stdout with reason + evidence +
# override hint:
#
#   REFUSED  any file inside the caller's content scope has uncommitted
#            changes. A stamp written now would not honestly reflect HEAD
#            (dirty files aren't in the commit the stamp records), so refuse
#            before doing any work.
#   SKIPPED  the stamp file exists, points to an ancestor of HEAD, and no
#            file in the caller's content scope has changed between that
#            ancestor and HEAD — re-running the command would produce an
#            identical result.
#   RUNNING  normal execution. No stamp, or the stamp is orphaned (not an
#            ancestor of HEAD — branch switch, rebase, unknown commit), or
#            in-scope content drifted since the stamp.
#
# Escape hatches:
#   FORCE=1              bypass all guards, always run + stamp.
#   rm tmp/<stamp>       force next invocation from SKIP to RUN.
#
# Arguments: <command_label> <stamp_basename> <scope_path...>
# REFUSE and SKIP share the same scope — the files the command actually
# consumes. Fast-test passes "migrations test"; types/db-docs pass just
# "migrations". Non-strict baseline paths (test/expected/explain,
# test/expected/performance) are always excluded from dirty-checks: they
# drift with environment and shouldn't block a release.
#
# Return codes: 0 = RUN (continue), 1 = SKIP (caller should exit 0),
#               2 = REFUSE (caller should exit 1).
check_stamp_guard() {
    local label="$1"
    local stamp_basename="$2"
    shift 2
    local scopes=("$@")
    local stamp_path="$WORKSPACE/tmp/$stamp_basename"
    # Non-strict baselines: routine environment drift, never block release.
    local excludes=(':!test/expected/explain/' ':!test/expected/performance/')

    if [ "${FORCE:-}" = "1" ] || [ "${FORCE:-}" = "true" ]; then
        echo "RUNNING: $label"
        echo "Reason:  FORCE=1 — guard bypassed."
        return 0
    fi

    # RUN_NO_STAMP (rc 3): any file inside the scope (minus excludes) has
    # uncommitted staged or unstaged changes — you're (almost certainly) landing
    # a migration. RUN the work but DO NOT write the freshness stamp: a stamp from
    # a dirty tree can't honestly point at a commit (FORCE=1's old escape did
    # exactly that). The release preflight RE-DERIVES freshness (release.go
    # checkMigrationStamp), so withholding is fail-safe — after the commit a
    # clean-tree re-run writes an honest stamp. No override needed.
    local dirty
    dirty=$(git -C "$WORKSPACE" status --porcelain -- "${scopes[@]}" "${excludes[@]}" 2>/dev/null)
    if [ -n "$dirty" ]; then
        echo "RUNNING: $label — freshness stamp DEFERRED"
        echo "Reason:  uncommitted changes in ${scopes[*]} — running now, but NOT writing the"
        echo "         freshness stamp (a stamp from a dirty tree can't honestly point at a"
        echo "         commit). Release preflight re-derives freshness, so after you commit,"
        echo "         re-run this on a clean tree to write the stamp."
        echo "If you're landing a migration, the full no-override flow is:"
        echo "  1. ./sb migrate up --target seed && ./dev.sh create-test-template   # seed->HEAD (non-destructive)"
        echo "  2. ./dev.sh generate-doc-db && ./sb types generate                  # regenerate"
        echo "  3. git add migrations/ doc/db/ app/src/lib/database.types.ts <your code>"
        echo "  4. git commit                                                       # pre-commit pairs migration+regen"
        echo "  5. after commit (clean tree) re-run step 2 once -> writes the release stamp"
        echo "Do NOT FORCE=1 to land a migration — it writes a stamp from a dirty tree, the exact"
        echo "lie this guard prevents. FORCE=1 is only for regenerating against an already-committed"
        echo "schema (e.g. a generator change with no new migration)."
        echo "Evidence (uncommitted in ${scopes[*]}):"
        printf '%s\n' "$dirty" | sed 's/^/  /'
        return 3
    fi

    if [ ! -f "$stamp_path" ]; then
        echo "RUNNING: $label"
        echo "Reason:  no stamp at tmp/$stamp_basename — no prior successful run to skip."
        return 0
    fi

    # Two-line stamp format: line 1 = HEAD SHA, line 2 = source DB
    # migration_version. Extract line 1 for the freshness check below.
    # Pre-upgrade legacy stamps have only line 1; the count check after
    # this one catches and force-RUNs them so the generator upgrades the
    # stamp format on next run. Without that short-circuit, an operator
    # with a legacy stamp + no migrations-changed gets stuck in a SKIP
    # loop: preflight refuses the stamp ("legacy single-line"), generator
    # SKIPs because the stamp's SHA still matches HEAD's migrations.
    local stamp_sha
    stamp_sha=$(head -n 1 "$stamp_path" 2>/dev/null | tr -d '[:space:]')
    if [ -z "$stamp_sha" ]; then
        echo "RUNNING: $label"
        echo "Reason:  stamp tmp/$stamp_basename is empty."
        return 0
    fi

    # Legacy single-line stamp detection. Two-line stamps have ≥2
    # non-blank lines (SHA + migration_version); legacy stamps have 1.
    # Force RUN so the generator writes the upgraded format. awk 'NF>0'
    # filters non-blank lines, wc -l counts them.
    local non_blank_lines
    non_blank_lines=$(awk 'NF>0' "$stamp_path" 2>/dev/null | wc -l | tr -d ' ')
    if [ "${non_blank_lines:-0}" -lt 2 ]; then
        echo "RUNNING: $label"
        echo "Reason:  legacy single-line stamp at tmp/$stamp_basename — two-line format required by preflight."
        return 0
    fi

    if ! git -C "$WORKSPACE" merge-base --is-ancestor "$stamp_sha" HEAD 2>/dev/null; then
        echo "RUNNING: $label"
        echo "Reason:  stamp SHA $stamp_sha is not an ancestor of HEAD (branch switch, rebase, or unknown commit)."
        return 0
    fi

    local head_sha
    head_sha=$(git -C "$WORKSPACE" rev-parse HEAD 2>/dev/null)

    local changed
    changed=$(git -C "$WORKSPACE" diff --name-only "$stamp_sha" HEAD -- "${scopes[@]}" 2>/dev/null)
    if [ -z "$changed" ]; then
        # Version-coherence check: the SHA-diff axis says "no change" but the
        # stamp's source-DB version (line 2) must ALSO match HEAD's on-disk max
        # migration. If they diverge, release.go preflight would refuse this
        # stamp — the "catch-22" scenario where a migration was applied to dev
        # DB then later reverted (file deleted from tree). RUNNING so regen
        # writes a fresh, coherent stamp and breaks the loop.
        local stamp_version disk_max_version
        stamp_version=$(sed -n '2p' "$stamp_path" 2>/dev/null | tr -d '[:space:]')
        disk_max_version=$(find "$WORKSPACE/migrations" -maxdepth 1 \
            \( -name '*.up.sql' -o -name '*.up.psql' \) 2>/dev/null \
            | sed -E 's|.*/([0-9]{14})_.*|\1|' | sort -r | head -1)
        if [ -n "$stamp_version" ] && [ -n "$disk_max_version" ] && \
           [ "$stamp_version" != "$disk_max_version" ]; then
            echo "RUNNING: $label"
            echo "Reason:  SHA-diff is empty but stamp's source-DB version ($stamp_version)"
            echo "         != HEAD's on-disk max migration ($disk_max_version)."
            echo "         release.go preflight would refuse this stamp; regen must run."
            echo "         (catch-22: migration applied to dev DB then reverted from tree)"
            echo "Evidence:"
            echo "  stamp SHA: $stamp_sha"
            echo "  stamp source-DB version: $stamp_version"
            echo "  HEAD on-disk max migration: $disk_max_version"
            return 0
        fi
        echo "SKIPPED: $label"
        echo "Reason:  stamp tmp/$stamp_basename points to a commit whose ${scopes[*]} content matches HEAD — re-running would produce an identical result."
        echo "Evidence:"
        echo "  stamp SHA: $stamp_sha"
        echo "  HEAD SHA:  $head_sha"
        echo "  files changed in scope (${scopes[*]}): 0"
        echo "Override: rm tmp/$stamp_basename, or set FORCE=1."
        return 1
    fi

    echo "RUNNING: $label"
    echo "Reason:  in-scope content has drifted since stamp."
    echo "Evidence:"
    echo "  stamp SHA: $stamp_sha"
    echo "  HEAD SHA:  $head_sha"
    echo "  files changed in scope (${scopes[*]}):"
    printf '%s\n' "$changed" | sed 's/^/    /'
    return 0
}

# the bash assert_db_at_head() helper has moved to Go.
# Single source of truth lives in cli/internal/migrate/at_head.go and is
# exposed at the CLI surface as `./sb assert-db-at-head <db_name> <caller>`.
# Reasons for the move:
#   - The Go path can hold a PG advisory lock during the query window
#     (shared variant of hashtext('statbus_seed_mutate')), serialising
#     against `./sb db with-seed-lock --exclusive` so a parallel
#     recreate-seed doesn't drop statbus_seed mid-query.
#   - Two implementations of the same diagnostic-shape contract is one
#     too many. Drift between the bash and Go copies has bitten us
#     before (template-vs-seed targeting, preflight ordering); the
#     bash copy is now retired.

action=${1:-}
shift || true

# ── Expected-output guardrail ─────────────────────────────────────────
#
# Used by `./dev.sh test ... --update-expected` and `make-all-failed-test-
# results-expected`. Detects NEW ERROR/FATAL/PANIC lines that the regen
# would introduce into a test/expected/*.out file. If any new error
# lacks a WANTED-context marker in the surrounding result (SAVEPOINT,
# \set ON_ERROR_STOP off, DO $$ EXCEPTION block, or "-- expected to
# fail" comment), BLOCK the regen with an educational message.
#
# Rationale: silently baselining a real error into expected hides bugs
# from CI. Future runs match the bug; everyone forgets it's there; it
# grows roots. This forces a deliberate decision at regen time.
#
# Cascade errors ("current transaction is aborted, commands ignored")
# are skipped — consequences of an earlier ERROR, not new failures.
#
# Override (rare, deliberate): ACCEPT_NEW_ERRORS=true

_unmarked_new_errors=""

_has_wanted_marker() {
  local file="$1" center_line="$2"
  local start=$((center_line - 10))
  [ $start -lt 1 ] && start=1
  local end=$((center_line + 5))
  sed -n "${start},${end}p" "$file" | grep -qE '\\set ON_ERROR_STOP off|^SAVEPOINT[[:space:]]+[a-zA-Z_][a-zA-Z0-9_]*|^DO[[:space:]]+\$\$|--[[:space:]]*(expected|will|should)[[:space:]]+(to[[:space:]]+)?(fail|error)'
}

_check_new_errors() {
  local expected="$1" result="$2"
  _unmarked_new_errors=""

  local error_linenums
  if [ ! -f "$expected" ]; then
    error_linenums=$(grep -nE '^(ERROR|FATAL|PANIC):' "$result" 2>/dev/null | cut -d: -f1 || true)
  else
    error_linenums=$(diff -u "$expected" "$result" 2>/dev/null | awk '
      /^@@/ {
        for (i = 1; i <= NF; i++) {
          if ($i ~ /^\+/) {
            sub(/^\+/, "", $i)
            split($i, a, ",")
            new_line = a[1] - 1
            break
          }
        }
        next
      }
      /^---/ || /^\+\+\+/ { next }
      /^\+/ {
        new_line++
        if (/^\+(ERROR|FATAL|PANIC):/) print new_line
        next
      }
      /^-/ { next }
      { new_line++ }
    ' || true)
  fi

  [ -z "$error_linenums" ] && return 0

  local lineno line_text
  while IFS= read -r lineno; do
    [ -z "$lineno" ] && continue
    line_text=$(sed -n "${lineno}p" "$result")
    if echo "$line_text" | grep -q "current transaction is aborted"; then
      continue
    fi
    if ! _has_wanted_marker "$result" "$lineno"; then
      _unmarked_new_errors="${_unmarked_new_errors}  ${expected#$WORKSPACE/}:${lineno}: ${line_text}"$'\n'
    fi
  done <<< "$error_linenums"

  [ -z "$_unmarked_new_errors" ] && return 0
  return 1
}

safe_update_expected() {
  local result="$1" expected="$2"
  if _check_new_errors "$expected" "$result"; then
    cp "$result" "$expected"
    return 0
  fi

  if [ "${ACCEPT_NEW_ERRORS:-false}" = "true" ]; then
    echo "  WARNING (ACCEPT_NEW_ERRORS=true override): baselining unmarked error(s):" >&2
    printf '%s' "$_unmarked_new_errors" >&2
    cp "$result" "$expected"
    return 0
  fi

  cat >&2 <<EOF

═══════════════════════════════════════════════════════════════════════
BLOCKED: ${expected#$WORKSPACE/} would gain ERROR/FATAL/PANIC line(s) without WANTED-context markers.

Unmarked new error(s):
${_unmarked_new_errors}
WHY: silently baselining unexpected errors into expected files hides
bugs from CI. Future runs match the bug; everyone forgets it's there;
it grows roots.

FIX OPTIONS:

  1. INTENTIONAL (bug-capture for TDD, or testing a failure path)
     — add an explicit marker to the test SQL:
       - Wrap in SAVEPOINT sp_<name> / ROLLBACK TO SAVEPOINT sp_<name>, OR
       - Bracket with \\set ON_ERROR_STOP off ... \\set ON_ERROR_STOP on, OR
       - Use DO \$\$ ... EXCEPTION WHEN ... END \$\$ for assertions, OR
       - Add a comment immediately before the failing line:
           -- expected to fail with <error class>
     Then re-run regen. The marker travels into the expected output
     and the guardrail recognises the intent.

  2. ACCIDENTAL (a real bug surfacing) — FIX THE TEST SQL.
     Don't baseline the bug. Investigate the failure first.

  3. Deliberate override (rare; cite reason in commit message):
       ACCEPT_NEW_ERRORS=true ./dev.sh ${action} ...

Hook source: dev.sh safe_update_expected
═══════════════════════════════════════════════════════════════════════
EOF
  exit 1
}

# ── Test-run serialization lock ───────────────────────────────────────
#
# NORTH STAR: two invocations that touch the shared pg_regress state
# (statbus_seed / statbus_test_template / the dev database) must never
# overlap — concurrent clones and drops corrupt each other and manufacture
# "flaky" failures that are not real ("there are no flaky tests"). We
# serialize DIRECTLY: an entrypoint that touches shared state takes an
# exclusive lock first; on contention it FAILS LOUDLY naming the holder —
# it never queues silently and never proceeds.
#
# MECHANISM: a real kernel lock — flock(2). flock(1) is absent on macOS
# (`command -v flock` exits non-zero here) and we can't call syscall.Flock
# from bash, but perl (5.x, always shipped on macOS + Linux) can flock a file
# descriptor INHERITED from the shell. We `exec 9>>lockfile` in bash, then
# perl fdopens fd 9 and takes flock(LOCK_EX|LOCK_NB). The lock lives with the
# open file DESCRIPTION behind fd 9, which gives three properties a userspace
# mkdir/pidfile lock cannot:
#   - No TOCTOU. The kernel grants the lock atomically; there is no
#     read-holder-then-reclaim window where two runs can both win.
#   - Released on process-tree death, even SIGKILL — the kernel drops the lock
#     when the LAST descriptor on the description closes. No EXIT trap needed.
#   - Held while any CHILD of a killed run is still alive: children inherit
#     fd 9, so a SIGKILL'd parent whose psql/docker child is still mutating the
#     DB keeps the lock until that child exits. (kill -0 on the parent pid, by
#     contrast, would false-reclaim mid-mutation, and PID reuse could false-block.)
# The holder file is now purely INFORMATIONAL — it names the holder in the
# contention banner; it is NOT the mutex, so a race to write it is harmless.
#
# RE-ENTRANCY: composite entrypoints spawn leaf ones as child `./dev.sh`
# processes (migrate-and-test → recreate-seed/create-test-template/test;
# create-db → create-db-structure/recreate-seed/create-test-template;
# recreate-database → delete-db/create-db). The outermost process exports
# STATBUS_TEST_LOCK_HELD; children see it and pass through (they already
# inherited fd 9, which keeps the lock held for their lifetime), so the lock
# is taken once and released once, by the top of the process tree.
_TEST_LOCK_FILE="$WORKSPACE/tmp/.test-run.lock"
_TEST_LOCK_INFO="$WORKSPACE/tmp/.test-run.lock.info"
_TEST_LOCK_OWNED=false   # true ONLY in the process that took the lock

release_test_run_lock() {
    # Idempotent; a no-op unless THIS process took the lock. Child processes
    # inherited STATBUS_TEST_LOCK_HELD and never acquired, so their
    # _TEST_LOCK_OWNED stays false and they cannot release the parent's lock.
    # The kernel also releases on exit; closing fd 9 here makes it prompt on a
    # clean exit and clears the informational holder file.
    if [ "$_TEST_LOCK_OWNED" = true ]; then
        # NB: no `2>/dev/null` on a no-command `exec` — it would permanently
        # redirect THIS shell's stderr, not just silence the close. fd 9 is
        # guaranteed open here (we own the lock), so the bare close won't error.
        exec 9>&- || true
        rm -f "$_TEST_LOCK_INFO" 2>/dev/null || true
        _TEST_LOCK_OWNED=false
    fi
}

# ── STATBUS-158: straggler pg_regress guard + NUL-corruption tripwire ──
#
# WHY: the flock above lives on a HOST file descriptor and is released the
# instant this process tree dies, even via SIGKILL — but pg_regress runs
# INSIDE the db container via `docker compose exec`, spawned by containerd,
# and does NOT inherit that fd. Kill a harness run after pg_regress starts
# and the flock frees immediately while pg_regress (or its psql child, if
# pg_regress itself died first) keeps running and writing in the container.
# The next invocation then acquires the lock legitimately and starts a
# SECOND pg_regress into the same --outputdir — two writers on one .out
# file corrupt it silently: writer B's fopen truncates and writes its head,
# writer A's next flush lands at its own saved offset, and the kernel
# zero-fills the gap — a sparse NUL hole with correct content on both
# sides, no error from either writer.
#
# MATCH: 'pg_regress' catches the parent binary while it's still alive;
# 'HIDE_TABLEAM' catches its regress-runner psql children even after
# pg_regress itself has died and the child was reparented — empirically
# confirmed live (2026-07-12): a running pg_regress's psql child carries
# exactly `-v HIDE_TABLEAM=on -v HIDE_TOAST_COMPRESSION=on` and nothing
# else identifying it as a regress child (pg_regress redirects the child's
# stdin/stdout via fork+dup2, not a shell string, so the child's own argv
# never mentions the outputdir — matching on the path alone would miss an
# orphaned child once its parent is gone). HIDE_TABLEAM/HIDE_TOAST_COMPRESSION
# are psql -v vars only pg_regress injects; no real usage collides with them.
#
# NO AUTO-KILL (no-standing-self-heal rule): refuse loudly, name the exact
# pids + kill command, and let the operator decide — recurrence must fail
# loudly with the fix named, never be quietly repaired out from under them.
check_no_straggler_pg_regress() {
    # If the db service isn't even running there is nothing to race with —
    # docker compose exec fails fast in that case; skip silently.
    local _straggler
    _straggler=$(docker compose exec -T db pgrep -af 'pg_regress|HIDE_TABLEAM' 2>/dev/null) || return 0
    [ -n "$_straggler" ] || return 0

    local _pids
    _pids=$(printf '%s\n' "$_straggler" | awk '{print $1}' | tr '\n' ' ')

    cat >&2 <<EOF

═══════════════════════════════════════════════════════════════════════
BLOCKED: a straggler pg_regress is still running in the db container.

This command is about to start pg_regress against the shared outputdir
(test/results/). A PREVIOUS harness run's pg_regress (or its psql child)
is still alive in the db container even though the host-side test-run
lock is free — the lock lives on a host file descriptor and does not
reach into the container, so a killed run can leave pg_regress orphaned
there, still writing into the same .out files this run is about to
reuse. Two writers on one .out file corrupt it silently, with no error
from either side (STATBUS-158).

Straggler process(es) found in the db container:
$_straggler

WHAT TO DO:
  - Confirm these are truly orphaned (not a run you intend to keep), then
    kill them from the host:
      docker compose exec db kill -9 $_pids
  - Re-run this command once the container shows none left:
      docker compose exec db pgrep -af 'pg_regress|HIDE_TABLEAM'

Hook source: dev.sh check_no_straggler_pg_regress
═══════════════════════════════════════════════════════════════════════
EOF
    exit 1
}

# check_results_for_nul_corruption — the tripwire half of STATBUS-158. An
# embedded NUL in a pg_regress .out file is never legitimate output — psql
# and postgres never emit one; it is the fingerprint of two writers racing
# the same file (see check_no_straggler_pg_regress above) or any other
# write-layer fault. Preserve the corrupted bytes BEFORE anything reruns
# and overwrites them (the original STATBUS-158 incident lost its own byte
# schedule to exactly that overwrite), then fail with a verdict distinct
# from an ordinary test diff, naming the straggler check as the first thing
# to run. Args: <PG_REGRESS_DIR> <test_basename>...
check_results_for_nul_corruption() {
    local _dir="$1"; shift
    local _test _file _full _stripped _preserved _corrupted=""
    for _test in "$@"; do
        _file="$_dir/results/$_test.out"
        [ -f "$_file" ] || continue
        _full=$(wc -c < "$_file" | tr -d ' ')
        _stripped=$(LC_ALL=C tr -d '\000' < "$_file" | wc -c | tr -d ' ')
        if [ "$_full" != "$_stripped" ]; then
            mkdir -p "$WORKSPACE/tmp"
            _preserved="$WORKSPACE/tmp/corrupted-$_test-$(date '+%Y%m%d%H%M%S' 2>/dev/null || echo unknown).out"
            if ! cp "$_file" "$_preserved" 2>/dev/null; then
                _preserved="(preservation FAILED — original left at $_file)"
            fi
            _corrupted="$_corrupted  $_test -> $_preserved
"
        fi
    done
    [ -n "$_corrupted" ] || return 0

    cat >&2 <<EOF

═══════════════════════════════════════════════════════════════════════
CORRUPTED OUTPUT: embedded NUL byte(s) found in a test result file.

A .out file pg_regress just wrote contains an embedded NUL byte — psql and
postgres never emit one; this is the fingerprint of two pg_regress writers
racing the same file (a straggler from a killed run — see
check_no_straggler_pg_regress / STATBUS-158), not a real test failure.

Corrupted file(s), preserved before any rerun can overwrite them:
$_corrupted
WHAT TO DO:
  - Check for a straggler right now:
      docker compose exec db pgrep -af 'pg_regress|HIDE_TABLEAM'
  - If found, kill it, THEN re-run this test — do not trust its diff, it
    was never a real second failure.

Hook source: dev.sh check_results_for_nul_corruption
═══════════════════════════════════════════════════════════════════════
EOF
    return 1
}

acquire_test_run_lock() {
    local _label="${1:-./dev.sh}"
    # Re-entrant: an ancestor dev.sh already holds it → pass through.
    if [ -n "${STATBUS_TEST_LOCK_HELD:-}" ]; then
        return 0
    fi
    mkdir -p "$WORKSPACE/tmp"
    # Self-heal the one-time transition from the retired mkdir-based lock: if a
    # leftover DIRECTORY sits at the lockfile path (e.g. a mkdir-era run was
    # SIGKILL'd before its rmdir), clear it so `exec 9>>` doesn't error with
    # "Is a directory". Only ever a directory under the retired scheme; the
    # flock scheme always uses a plain file.
    if [ -d "$_TEST_LOCK_FILE" ]; then rm -rf "$_TEST_LOCK_FILE" 2>/dev/null || true; fi
    # Open fd 9 on the lockfile for the rest of this process's life. Every child
    # inherits it; the kernel keeps the lock held until the whole tree closes it.
    exec 9>>"$_TEST_LOCK_FILE" || {
        echo "test-run lock: cannot open lockfile $_TEST_LOCK_FILE — refusing to run unserialized." >&2
        exit 1
    }
    # Take flock(2) via perl on the inherited fd. rc: 0 acquired, 1 would-block
    # (a live run holds it), anything else (3 fdopen failed, 127 no perl, …) is
    # an environment fault — in every non-zero case we refuse rather than run
    # two suites against the shared templates at once.
    local _prc=0
    perl -e 'open(my $fh, ">&=", 9) or exit 3; use Fcntl qw(:flock); exit(flock($fh, LOCK_EX|LOCK_NB) ? 0 : 1);' || _prc=$?
    if [ "$_prc" -eq 0 ]; then
        # Acquired. Record the holder for any contender's banner (informational).
        printf 'pid %s\nstarted-at %s\naction %s\n' \
            "$$" "$(date '+%Y-%m-%d %H:%M:%S %z' 2>/dev/null || echo unknown)" "$_label" \
            > "$_TEST_LOCK_INFO" 2>/dev/null || true
        _TEST_LOCK_OWNED=true
        export STATBUS_TEST_LOCK_HELD="$_TEST_LOCK_FILE"
        trap release_test_run_lock EXIT
        # STATBUS-158 AC#3: the straggler check lives INSIDE the function that
        # takes the lock — every caller that acquires the lock gets the check
        # for free; there is no separate call site to forget it at.
        check_no_straggler_pg_regress
        return 0
    fi
    exec 9>&- || true   # we did NOT acquire — drop our fd (no `2>…`: see release)
    local _info
    _info=$(sed 's/^/  /' "$_TEST_LOCK_INFO" 2>/dev/null || true)
    [ -n "$_info" ] || _info="  (holder info unavailable — the run started moments ago)"
    if [ "$_prc" -ne 1 ]; then
        echo "test-run lock: could not take flock via perl (rc=$_prc) — refusing to run unserialized. Is perl available?" >&2
        exit 1
    fi
    cat >&2 <<EOF

═══════════════════════════════════════════════════════════════════════
BLOCKED: another test run holds the test-run lock.

This command ($_label) touches the shared pg_regress state (statbus_seed /
statbus_test_template / the dev database). Two runs that touch it at once
corrupt each other and manufacture failures that are not real. Only one may
run at a time.

Current holder:
$_info

WHAT TO DO:
  - Wait for that run to finish, then retry (the lock releases the moment the
    holding process tree exits — no manual cleanup, even after a SIGKILL).
  - Lockfile: $_TEST_LOCK_FILE

Hook source: dev.sh acquire_test_run_lock
═══════════════════════════════════════════════════════════════════════
EOF
    exit 1
}

# Serialize the entrypoints that touch shared DB state or run the suite.
# Composites are included; their child `./dev.sh` calls inherit the lock via
# STATBUS_TEST_LOCK_HELD and pass through, so the whole composite is one
# critical section. `continous-integration-test` is intentionally NOT here:
# it runs on isolated CI runners, and it drives the above as children, each
# of which takes the lock — so a concurrent dev command still contends.
case "$action" in
    test|test-isolated|migrate-and-test|\
    create-db|create-db-structure|reset-db-structure|\
    delete-db|delete-db-structure|recreate-database|\
    create-test-template|create-seed|delete-seed|recreate-seed|\
    seed-clone|clean-test-databases )
        acquire_test_run_lock "./dev.sh $action${*:+ $*}"
        ;;
esac

case "$action" in
    'postgres-variables' )
        SITE_DOMAIN=$(./sb dotenv -f .env get SITE_DOMAIN || echo "local.statbus.org")
        CADDY_DEPLOYMENT_MODE=$(./sb dotenv -f .env get CADDY_DEPLOYMENT_MODE || echo "development")
        PGDATABASE=$(./sb dotenv -f .env get POSTGRES_APP_DB)
        PGUSER=${PGUSER:-$(./sb dotenv -f .env get POSTGRES_ADMIN_USER)}
        PGPASSWORD=$(./sb dotenv -f .env get POSTGRES_ADMIN_PASSWORD)
        PGHOST=$SITE_DOMAIN

        if [ "${TLS:-}" = "1" ] || [ "${TLS:-}" = "true" ]; then
            PGPORT=$(./sb dotenv -f .env get CADDY_DB_TLS_PORT)
            PGSSLNEGOTIATION=direct
            PGSSLMODE=require
            PGSSLSNI=1
            POSTGRES_TEST_DB=$(./sb dotenv -f .env get POSTGRES_TEST_DB 2>/dev/null || echo "statbus_test_template")
            cat <<EOS
export PGHOST=$PGHOST PGPORT=$PGPORT PGDATABASE=$PGDATABASE PGUSER=$PGUSER PGPASSWORD=$PGPASSWORD PGSSLMODE=$PGSSLMODE PGSSLNEGOTIATION=$PGSSLNEGOTIATION PGSSLSNI=$PGSSLSNI POSTGRES_TEST_DB=$POSTGRES_TEST_DB
EOS
        else
            PGPORT=$(./sb dotenv -f .env get CADDY_DB_PORT)
            PGSSLMODE=disable
            POSTGRES_TEST_DB=$(./sb dotenv -f .env get POSTGRES_TEST_DB 2>/dev/null || echo "statbus_test_template")
            cat <<EOS
export PGHOST=$PGHOST PGPORT=$PGPORT PGDATABASE=$PGDATABASE PGUSER=$PGUSER PGPASSWORD=$PGPASSWORD PGSSLMODE=$PGSSLMODE POSTGRES_TEST_DB=$POSTGRES_TEST_DB
EOS
        fi
      ;;
    'is-db-running' )
        docker compose exec -T db pg_isready -U postgres > /dev/null 2>&1
      ;;
    'continous-integration-test' )
        BRANCH=${BRANCH:-${1:-}}
        COMMIT=${COMMIT:-${2:-}}

        if [ -z "$BRANCH" ]; then
            BRANCH=$(git rev-parse --abbrev-ref HEAD)
            echo "No branch argument provided, using the currently checked-out branch $BRANCH"
        else
            if ! git diff-index --quiet HEAD --; then
                echo "Error: Repository has uncommitted changes. Please commit or stash changes before switching branches."
                exit 1
            fi
            git fetch origin
            if [ -z "$COMMIT" ]; then
                echo "Error: Commit hash must be provided."
                exit 1
            fi
            if ! git cat-file -e "$COMMIT" 2>/dev/null; then
                echo "Error: Commit '$COMMIT' is invalid or not found."
                exit 1
            fi
            echo "Checking out commit '$COMMIT' (from branch '$BRANCH')"
            git checkout "$COMMIT"
        fi

        # Build sb from source if it doesn't exist or is outdated.
        # The test server may not have a pre-built binary.
        if [ ! -x ./sb ] || ! ./sb --version >/dev/null 2>&1; then
            echo "Building sb from source..."
            _SB_VERSION=$(git describe --tags --always --match 'v[0-9]*' 2>/dev/null || echo "dev")
            # Full 40-char SHA — see note at line ~51 for rationale.
            _SB_COMMIT=$(git rev-parse HEAD 2>/dev/null || echo "unknown")
            _SB_LDFLAGS="-X 'github.com/statisticsnorway/statbus/cli/cmd.version=${_SB_VERSION}' -X 'github.com/statisticsnorway/statbus/cli/cmd.commit=${_SB_COMMIT}'"
            (cd cli && go build -ldflags "$_SB_LDFLAGS" -o ../sb .)
        fi

        ./sb config generate

        # Pull pre-built Docker images from ghcr.io if available.
        # CI Images workflow builds sha-tagged images for every master push.
        if [ -n "$COMMIT" ]; then
            echo "Pulling cached Docker images for sha-${COMMIT}..."
            VERSION="sha-${COMMIT}" docker compose pull --quiet 2>/dev/null || echo "No cached images, will build locally"
        fi

        ./dev.sh delete-db

        ./dev.sh create-db > /dev/null
        trap './dev.sh delete-db > /dev/null' EXIT

        TEST_OUTPUT=$(mktemp)
        # Use the auto-fix composition for CI: bootstraps seed +
        # test template if a fresh runner needs them. Human-facing
        # `./dev.sh test fast` is check-don't-fix; this path is the
        # CI-friendly equivalent. Plan section R commit 4.
        ./dev.sh migrate-and-test fast 2>&1 | tee "$TEST_OUTPUT" || true

        if grep -q "not ok" "$TEST_OUTPUT" || grep -q "of .* tests failed" "$TEST_OUTPUT"; then
            echo "One or more tests failed."
            echo "Test summary:"
            grep -A 20 "======================" "$TEST_OUTPUT"

            if command -v delta >/dev/null 2>&1; then
                echo "Showing the color-coded diff:"
                docker compose exec --workdir /statbus db cat /statbus/test/regression.diffs | delta
            else
                echo "Error: 'delta' tool is not installed. Install with: brew install git-delta"
                echo "Showing raw diff:"
                docker compose exec --workdir /statbus db cat /statbus/test/regression.diffs
            fi
            exit 1
        else
            echo "All tests passed successfully."
        fi
      ;;
    'test' )
        eval $(./dev.sh postgres-variables)

        POSTGRESQL_MAJOR=$(grep -E "^ARG postgresql_major=" "$WORKSPACE/postgres/Dockerfile" | cut -d= -f2)
        if [ -z "$POSTGRESQL_MAJOR" ]; then
            echo "Error: Could not extract PostgreSQL major version from Dockerfile"
            exit 1
        fi

        PG_REGRESS_DIR="$WORKSPACE/test"
        PG_REGRESS="/usr/lib/postgresql/$POSTGRESQL_MAJOR/lib/pgxs/src/test/regress/pg_regress"
        CONTAINER_REGRESS_DIR="/statbus/test"

        for suffix in "sql" "expected" "results"; do
            if ! test -d "$PG_REGRESS_DIR/$suffix"; then
                mkdir -p "$PG_REGRESS_DIR/$suffix"
            fi
        done

        ORIGINAL_ARGS=("$@")

        update_expected=false
        TEST_ARGS=()
        if [ ${#ORIGINAL_ARGS[@]} -gt 0 ]; then
            for arg in "${ORIGINAL_ARGS[@]}"; do
                if [ "$arg" = "--update-expected" ]; then
                    update_expected=true
                else
                    TEST_ARGS+=("$arg")
                fi
            done
        fi

        if [ ${#TEST_ARGS[@]} -eq 0 ]; then
            echo "Available tests:"
            echo "all"
            echo "fast"
            echo "benchmarks"
            echo "failed"
            basename -s .sql "$PG_REGRESS_DIR/sql"/*.sql
            exit 0
        fi

        # STATBUS-157: ONE shared predicate for "is this the full fast suite" —
        # used by BOTH the dirty-tree withhold guard and the stamp-write gate
        # below, so they cannot diverge again. Previously each site re-checked
        # `${TEST_ARGS[0]} = "fast"` independently; the withhold guard did, but
        # the stamp-write site instead only ever checked $OVERALL_EXIT_CODE — so
        # ANY successful `./dev.sh test <target>` (a single targeted test, not
        # just `fast`) wrote the freshness stamp, even on a dirty tree.
        IS_FAST_SUITE_RUN=false
        [ "${TEST_ARGS[0]}" = "fast" ] && IS_FAST_SUITE_RUN=true

        if [ "${TEST_ARGS[0]}" = "all" ]; then
            ALL_TESTS=$(basename -s .sql "$PG_REGRESS_DIR/sql"/*.sql)
            TEST_BASENAMES=""
            for test in $ALL_TESTS; do
                exclude=false
                for arg in "${TEST_ARGS[@]:1}"; do
                    if [ "$arg" = "-$test" ]; then
                        exclude=true
                        break
                    fi
                done
                if [ "$exclude" = "false" ]; then
                    TEST_BASENAMES="$TEST_BASENAMES $test"
                fi
            done
        elif [ "${TEST_ARGS[0]}" = "fast" ]; then
            ALL_TESTS=$(basename -s .sql "$PG_REGRESS_DIR/sql"/*.sql)
            TEST_BASENAMES=""
            for test in $ALL_TESTS; do
                exclude=false
                if [[ "$test" == 4* ]] || [[ "$test" == 5* ]]; then
                    exclude=true
                fi
                if [ "$exclude" = "false" ]; then
                    for arg in "${TEST_ARGS[@]:1}"; do
                        if [ "$arg" = "-$test" ]; then
                            exclude=true
                            break
                        fi
                    done
                fi
                if [ "$exclude" = "false" ]; then
                    TEST_BASENAMES="$TEST_BASENAMES $test"
                fi
            done
        elif [ "${TEST_ARGS[0]}" = "benchmarks" ]; then
            ALL_TESTS=$(basename -s .sql "$PG_REGRESS_DIR/sql"/*.sql)
            TEST_BASENAMES=""
            for test in $ALL_TESTS; do
                exclude=false
                if [[ "$test" != 4* ]]; then
                    exclude=true
                fi
                if [ "$exclude" = "false" ]; then
                    for arg in "${TEST_ARGS[@]:1}"; do
                        if [ "$arg" = "-$test" ]; then
                            exclude=true
                            break
                        fi
                    done
                fi
                if [ "$exclude" = "false" ]; then
                    TEST_BASENAMES="$TEST_BASENAMES $test"
                fi
            done
        elif [ "${TEST_ARGS[0]}" = "failed" ]; then
            FAILED_TESTS=$(grep -E '^not ok' $WORKSPACE/test/regression.out | sed -E 's/not ok[[:space:]]+[0-9]+[[:space:]]+- ([^[:space:]]+).*/\1/')
            TEST_BASENAMES=""
            for test in $FAILED_TESTS; do
                exclude=false
                for arg in "${TEST_ARGS[@]:1}"; do
                    if [ "$arg" = "-$test" ]; then
                        exclude=true
                        break
                    fi
                done
                if [ "$exclude" = "false" ]; then
                    TEST_BASENAMES="$TEST_BASENAMES $test"
                fi
            done
        else
            TEST_BASENAMES=""
            for arg in "${TEST_ARGS[@]}"; do
                if [[ "$arg" != -* ]]; then
                    TEST_BASENAMES="$TEST_BASENAMES $arg"
                fi
            done
        fi

        INVALID_TESTS=""
        for test_basename in $TEST_BASENAMES; do
            if [ ! -f "$PG_REGRESS_DIR/sql/$test_basename.sql" ]; then
                INVALID_TESTS="$INVALID_TESTS $test_basename"
            fi
        done

        if [ -n "$INVALID_TESTS" ]; then
            echo "Error: Test(s) not found:$INVALID_TESTS"
            echo ""
            echo "Available tests:"
            echo "  all    - Run all tests"
            echo "  fast       - Run all tests except 4xx/5xx (large imports)"
            echo "  benchmarks - Run only 4xx tests (performance benchmarks)"
            echo "  failed - Re-run previously failed tests"
            echo ""
            echo "Individual tests:"
            basename -s .sql "$PG_REGRESS_DIR/sql"/*.sql | sed 's/^/  /'
            exit 1
        fi

        # Tier-1 stamp guard — only on the `fast` selector, which writes
        # tmp/fast-test-passed-sha on success. Refuse dirty migrations (stamp
        # would lie), skip when the stamp still represents HEAD's migrations +
        # test content.
        if [ "$IS_FAST_SUITE_RUN" = "true" ]; then
            set +e
            check_stamp_guard "./dev.sh test fast" "fast-test-passed-sha" "migrations" "test"
            guard_rc=$?
            set -e
            case $guard_rc in
                0) FAST_STAMP_WITHHELD=0 ;;
                1) exit 0 ;;
                3) FAST_STAMP_WITHHELD=1 ;;  # RUN_NO_STAMP: run tests, withhold the stamp (dirty tree)
                # STATBUS-079: fail-fast on any rc outside the guard's 0/1/3 contract.
                # Without this, a future unhandled rc falls through silently →
                # FAST_STAMP_WITHHELD stays unset → :-0 writes a stamp on a dirty
                # tree (the exact silent-dirty-stamp class the gate fix prevents).
                *) echo "check_stamp_guard: unexpected rc $guard_rc" >&2; exit 1 ;;
            esac
        fi

        SHARED_TESTS=""
        ISOLATED_TESTS=""

        for test_basename in $TEST_BASENAMES; do
            expected_file="$PG_REGRESS_DIR/expected/$test_basename.out"
            if [ ! -f "$expected_file" ] && [ -f "$PG_REGRESS_DIR/sql/$test_basename.sql" ]; then
                echo "Warning: Expected output file $expected_file not found. Creating an empty placeholder."
                touch "$expected_file"
            fi
            if [[ "$test_basename" == 4* ]] || [[ "$test_basename" == 5* ]]; then
                ISOLATED_TESTS="$ISOLATED_TESTS $test_basename"
            else
                SHARED_TESTS="$SHARED_TESTS $test_basename"
            fi
        done

        debug_arg=""
        if [ "${DEBUG:-}" = "true" ] || [ "${DEBUG:-}" = "1" ]; then
          debug_arg="--debug"
        fi

        # Precondition (plan section R commit 4: check, don't fix —
        # consolidated to use the unified ./sb assert-db-at-head primitive).
        # `./dev.sh test ...` is human-facing — refuses to
        # run with stale state and prints the exact remediation command.
        # CI/automation that wants auto-rebuild should call
        # `./dev.sh migrate-and-test ...` instead.
        #
        # Assert against the SEED (canonical source-of-truth), not the
        # test_template. The seed/template chain
        # is: template_statbus → statbus_seed → statbus_test_template.
        # The test_template is intentionally non-connectable
        # (ALLOW_CONNECTIONS=false) so per-test clones go fast; querying
        # it directly silently returned 0 rows and produced a false
        # "BEHIND HEAD" diagnostic in the original wiring. The seed
        # IS the source of truth — when it's at HEAD, every clone
        # downstream (test_template, transient test DBs) is too by
        # construction. The test_template's freshness relative to the
        # seed is policed separately by the tmp/test-template-migrations-sha
        # stamp check that migrate-and-test fast enforces.
        #
        # SOURCE_VERSION captured for the H1 two-line stamp write below.
        SEED_NAME_PRECHECK="${POSTGRES_SEED_DB:-statbus_seed}"
        # migrated from the bash assert_db_at_head
        # function to the Go subcommand `./sb assert-db-at-head`, which
        # internally acquires a SHARED advisory lock on the
        # statbus_seed mutation key. That serialises against
        # `./sb db with-seed-lock --exclusive` so a parallel
        # recreate-seed doesn't drop statbus_seed mid-query.
        # A3: assert-db-at-head already prints a complete REFUSED / Reason / Fix
        # block whose Fix line is the seed/template rebuild command — don't echo
        # a second, near-identical remediation. With the binary-staleness noise
        # gone (A1/A2), this legitimate seed-drift refuse stands alone as one
        # actionable block.
        if ! SOURCE_VERSION=$(./sb assert-db-at-head "$SEED_NAME_PRECHECK" "./dev.sh test fast"); then
            exit 1
        fi

        OVERALL_EXIT_CODE=0

        if [ -n "$SHARED_TESTS" ]; then
            TEMPLATE_NAME="${POSTGRES_TEST_DB:-statbus_test_template}"
            SHARED_TEST_DB="test_shared_$$"

            TEMPLATE_EXISTS=$(./sb psql -d postgres -t -A -c \
                "SELECT 1 FROM pg_database WHERE datname = '$TEMPLATE_NAME';" 2>/dev/null || echo "0")
            if [ "$TEMPLATE_EXISTS" != "1" ]; then
                echo "Error: Template database '$TEMPLATE_NAME' not found."
                echo "Create it with: ./dev.sh create-test-template"
                exit 1
            fi

            echo "=== Running shared tests (BEGIN/ROLLBACK isolation on cloned database) ==="
            echo "Creating shared test database: $SHARED_TEST_DB from template $TEMPLATE_NAME"

            if ! ./sb psql -d postgres -v ON_ERROR_STOP=1 <<EOF
                SELECT pg_advisory_lock(59328);
                ALTER DATABASE $TEMPLATE_NAME WITH ALLOW_CONNECTIONS = true;
                CREATE DATABASE "$SHARED_TEST_DB" WITH TEMPLATE $TEMPLATE_NAME;
                ALTER DATABASE $TEMPLATE_NAME WITH ALLOW_CONNECTIONS = false;
                SELECT pg_advisory_unlock(59328);
EOF
            then
                echo "Error: Failed to create shared test database from template"
                exit 1
            fi

            cleanup_shared_test_db() {
                local exit_code=$?
                # This trap replaced the acquire-time release trap, so release
                # the test-run lock here too (idempotent; no-op if we don't own
                # it, e.g. when `test` runs as a child of migrate-and-test).
                release_test_run_lock
                if [ "${PERSIST:-false}" = "true" ]; then
                    echo "PERSIST=true: Keeping shared test database: $SHARED_TEST_DB"
                    return $exit_code
                fi
                if [ -n "$SHARED_TEST_DB" ]; then
                    echo "Cleaning up shared test database: $SHARED_TEST_DB"
                    ./sb psql -d postgres -c "DROP DATABASE IF EXISTS \"$SHARED_TEST_DB\";" 2>/dev/null || true
                fi
                return $exit_code
            }
            trap cleanup_shared_test_db EXIT

            docker compose exec --workdir "/statbus" db \
                $PG_REGRESS $debug_arg \
                --use-existing \
                --bindir="/usr/lib/postgresql/$POSTGRESQL_MAJOR/bin" \
                --inputdir=$CONTAINER_REGRESS_DIR \
                --outputdir=$CONTAINER_REGRESS_DIR \
                --dbname="$SHARED_TEST_DB" \
                --user=$PGUSER \
                $SHARED_TESTS || OVERALL_EXIT_CODE=$?

            # STATBUS-158 AC#2: an embedded NUL is never a legitimate test
            # failure — check regardless of pass/fail above.
            check_results_for_nul_corruption "$PG_REGRESS_DIR" $SHARED_TESTS || OVERALL_EXIT_CODE=1
        fi

        if [ -n "$ISOLATED_TESTS" ]; then
            echo ""
            echo "=== Running isolated tests (database-per-test from template) ==="
            for test_basename in $ISOLATED_TESTS; do
                update_arg=""
                if [ "$update_expected" = "true" ]; then
                    update_arg="--update-expected"
                fi
                ./dev.sh test-isolated "$test_basename" $update_arg || OVERALL_EXIT_CODE=$?
            done
        fi

        if [ "$update_expected" = "true" ] && [ -n "$SHARED_TESTS" ]; then
            echo "Updating expected output for shared tests: $(echo $SHARED_TESTS)"
            for test_basename in $SHARED_TESTS; do
                result_file="$PG_REGRESS_DIR/results/$test_basename.out"
                expected_file="$PG_REGRESS_DIR/expected/$test_basename.out"
                if [ -f "$result_file" ]; then
                    echo "  -> Copying results for $test_basename"
                    safe_update_expected "$result_file" "$expected_file"
                else
                    echo "Warning: Result file not found for test: '$test_basename'. Cannot update expected output."
                fi
            done
        fi

        # Write the stamp unconditionally on success of the FULL fast suite —
        # the upfront REFUSE guard already verified migrations/ and test/
        # (minus non-strict baselines) were clean at RUN time, AND
        # ./sb assert-db-at-head above confirmed the seed matches HEAD's
        # on-disk migrations, so HEAD + SOURCE_VERSION is an honest pair. No
        # silent skip: if we got here on a fast-suite run, we stamp.
        #
        # STATBUS-157: gated on the SAME $IS_FAST_SUITE_RUN predicate as the
        # withhold guard above — a targeted single-test run never reaches
        # this block at all, so it can neither write a stamp nor touch an
        # existing one, dirty tree or not.
        #
        # H1 two-line stamp:
        #   line 1: HEAD SHA at test-pass time
        #   line 2: source DB (test template) migration_version at test-pass time
        if [ "$IS_FAST_SUITE_RUN" = "true" ] && [ $OVERALL_EXIT_CODE -eq 0 ]; then
            if [ "${FAST_STAMP_WITHHELD:-0}" = "1" ]; then
                # RUN_NO_STAMP: tree was dirty at guard time — withhold the stamp.
                echo "Fast tests passed, but the freshness stamp was WITHHELD — migrations/ or test/"
                echo "had uncommitted changes at guard time. Commit, then re-run './dev.sh test fast'"
                echo "on a clean tree to write the release stamp (preflight requires it)."
            else
                mkdir -p "$WORKSPACE/tmp"
                {
                    git rev-parse HEAD
                    echo "$SOURCE_VERSION"
                } > "$WORKSPACE/tmp/fast-test-passed-sha"
                echo "Fast test stamp recorded: $(head -1 "$WORKSPACE/tmp/fast-test-passed-sha") (source version: $SOURCE_VERSION)"
            fi
        fi

        exit $OVERALL_EXIT_CODE
    ;;
    'migrate-and-test' )
        # CI-friendly composition (plan section R commit 4): bootstrap
        # the seed + test template if needed, then run tests. Auto-fix
        # complement to the human-facing `./dev.sh test ...` (which is
        # check-don't-fix).
        #
        # Use case: CI workflow on a fresh runner with no DB state, OR
        # a local cold workspace post-`git pull` with new migrations.
        # Bootstraps from cold to running tests in one command.
        eval $(./dev.sh postgres-variables)
        SEED_NAME="${POSTGRES_SEED_DB:-statbus_seed}"
        LATEST_MIGRATION=$(for f in "$WORKSPACE/migrations/"*.up.sql "$WORKSPACE/migrations/"*.up.psql; do
            [ -e "$f" ] || continue
            basename "$f" | cut -d_ -f1
        done | sort | tail -1)

        # Step 1: ensure seed exists and is at HEAD.
        SEED_EXISTS=$(./sb psql -d postgres -t -A -c \
            "SELECT 1 FROM pg_database WHERE datname = '$SEED_NAME';" 2>/dev/null || echo "0")
        SEED_MAX_VERSION=""
        if [ "$SEED_EXISTS" = "1" ]; then
            SEED_MAX_VERSION=$(./sb psql -d "$SEED_NAME" -t -A -c \
                "SELECT MAX(version) FROM db.migration" 2>/dev/null | tr -d ' ' || true)
        fi
        if [ "$SEED_EXISTS" != "1" ] || [ "$SEED_MAX_VERSION" != "$LATEST_MIGRATION" ]; then
            echo "migrate-and-test: seed bootstrap (exists=$SEED_EXISTS, version='$SEED_MAX_VERSION', want '$LATEST_MIGRATION')..."
            ./dev.sh recreate-seed
        else
            echo "migrate-and-test: seed already at $SEED_MAX_VERSION (matches HEAD)."
        fi

        # Step 2: ensure test template fresh.
        # STATBUS-126: the stamp keys on the migration CONTENT fingerprint
        # (./sb migrate fingerprint, cli/internal/migrate/fingerprint.go) —
        # not the max timestamp — so editing an already-applied migration's
        # bytes invalidates the template; an unchanged migrations/ directory
        # still fingerprints identically (no rebuild-every-run).
        if [ ! -x ./sb ] || ! ./sb --version >/dev/null 2>&1; then
            echo "Error: ./sb is missing or not runnable — cannot compute the migration content fingerprint." >&2
            echo "  Build it first: ./dev.sh cross-build-sb (or: cd cli && go build -o ../sb .)" >&2
            echo "  Refusing to guess template freshness without it." >&2
            exit 1
        fi
        CURRENT_FINGERPRINT=$(./sb migrate fingerprint) || { echo "Error: ./sb migrate fingerprint failed." >&2; exit 1; }
        TEMPLATE_STAMP=""
        if [ -f "$WORKSPACE/tmp/test-template-migrations-sha" ]; then
            TEMPLATE_STAMP=$(cat "$WORKSPACE/tmp/test-template-migrations-sha")
        fi
        if [ "$TEMPLATE_STAMP" != "$CURRENT_FINGERPRINT" ]; then
            echo "migrate-and-test: test template stale (content fingerprint changed). Rebuilding..."
            ./dev.sh create-test-template
        else
            echo "migrate-and-test: test template content fingerprint unchanged ($CURRENT_FINGERPRINT) — reusing."
        fi

        # Step 3: run tests with whatever args were passed.
        ./dev.sh test "$@"
    ;;
    'diff-fail-first' )
      if [ ! -f "$WORKSPACE/test/regression.out" ]; then
          echo "Error: File $WORKSPACE/test/regression.out not found."
          echo "Run tests first: ./dev.sh test fast"
          exit 1
      fi

      if [ ! -r "$WORKSPACE/test/regression.out" ]; then
          echo "Error: Cannot read $WORKSPACE/test/regression.out"
          exit 1
      fi

      test_line=$(grep -a -E '^not ok' "$WORKSPACE/test/regression.out" | head -n 1)

      if [[ "$test_line" =~ ^Binary\ file.*matches$ ]]; then
          echo "Error: Cannot parse test results. The regression.out file may be corrupted."
          echo "Try running tests again: ./dev.sh test fast"
          exit 1
      fi

      if [ -n "$test_line" ]; then
          test=$(echo "$test_line" | sed -E 's/not ok[[:space:]]+[0-9]+[[:space:]]+- ([^[:space:]]+).*/\1/')

          ui_choice=${1:-pipe}
          line_limit=${2:-}
          case $ui_choice in
              'gui')
                  echo "Running opendiff for test: $test"
                  opendiff $WORKSPACE/test/expected/$test.out $WORKSPACE/test/results/$test.out -merge $WORKSPACE/test/expected/$test.out
                  ;;
              'vim'|'tui')
                  echo "Running vim -d for test: $test"
                  vim -d $WORKSPACE/test/expected/$test.out $WORKSPACE/test/results/$test.out < "$TTY_INPUT"
                  ;;
              'vimo')
                  echo "Running vim -d -o for test: $test"
                  vim -d -o $WORKSPACE/test/expected/$test.out $WORKSPACE/test/results/$test.out < "$TTY_INPUT"
                  ;;
              'pipe')
                  echo "Running diff for test: $test"
                  if [[ "$line_limit" =~ ^[0-9]+$ ]]; then
                    diff $WORKSPACE/test/expected/$test.out $WORKSPACE/test/results/$test.out | head -n "$line_limit" || true
                  else
                    diff $WORKSPACE/test/expected/$test.out $WORKSPACE/test/results/$test.out || true
                  fi
                  ;;
              *)
                  echo "Error: Unknown UI option '$ui_choice'. Please use 'gui', 'vim', 'vimo', or 'pipe'."
                  exit 1
              ;;
          esac
      else
          echo "No failing tests found."
      fi
    ;;
    'diff-fail-all' )
      if [ ! -f "$WORKSPACE/test/regression.out" ]; then
          echo "Error: File $WORKSPACE/test/regression.out not found."
          echo "Run tests first: ./dev.sh test fast"
          exit 1
      fi

      if [ ! -r "$WORKSPACE/test/regression.out" ]; then
          echo "Error: Cannot read $WORKSPACE/test/regression.out"
          exit 1
      fi

      ui_choice=${1:-pipe}
      line_limit=${2:-}

      first_line=$(grep -a -E '^not ok' "$WORKSPACE/test/regression.out" | head -n 1)
      if [[ "$first_line" =~ ^Binary\ file.*matches$ ]]; then
          echo "Error: Cannot parse test results. The regression.out file may be corrupted."
          echo "Try running tests again: ./dev.sh test fast"
          exit 1
      fi

      if [ -z "$first_line" ]; then
          echo "No failing tests found in regression.out"
          exit 0
      fi

      while read test_line; do
          test=$(echo "$test_line" | sed -E 's/not ok[[:space:]]+[0-9]+[[:space:]]+- ([^[:space:]]+).*/\1/')

          if [ "$ui_choice" != "pipe" ]; then
              echo "Next test: $test"
              echo "Press C to continue, s to skip, or b to break (default: C)"
              read -n 1 -s input < "$TTY_INPUT"
              if [ "$input" = "b" ]; then
                  break
              elif [ "$input" = "s" ]; then
                  continue
              fi
          fi

          case $ui_choice in
              'gui')
                  echo "Running opendiff for test: $test"
                  opendiff $WORKSPACE/test/expected/$test.out $WORKSPACE/test/results/$test.out -merge $WORKSPACE/test/expected/$test.out
                  ;;
              'vim'|'tui')
                  echo "Running vim -d for test: $test"
                  vim -d $WORKSPACE/test/expected/$test.out $WORKSPACE/test/results/$test.out < "$TTY_INPUT"
                  ;;
              'vimo')
                  echo "Running vim -d -o for test: $test"
                  vim -d -o $WORKSPACE/test/expected/$test.out $WORKSPACE/test/results/$test.out < "$TTY_INPUT"
                  ;;
              'pipe')
                  echo "Running diff for test: $test"
                  if [[ "$line_limit" =~ ^[0-9]+$ ]]; then
                    diff $WORKSPACE/test/expected/$test.out $WORKSPACE/test/results/$test.out | head -n "$line_limit" || true
                  else
                    diff $WORKSPACE/test/expected/$test.out $WORKSPACE/test/results/$test.out || true
                  fi
                  ;;
              *)
                  echo "Error: Unknown UI option '$ui_choice'. Please use 'gui', 'vim', 'vimo', or 'pipe'."
                  exit 1
              ;;
          esac
      done < <(grep -a -E '^not ok' "$WORKSPACE/test/regression.out")
    ;;
    'make-all-failed-test-results-expected' )
        if [ ! -f "$WORKSPACE/test/regression.out" ]; then
            echo "Error: No regression.out file found."
            echo "Run tests first: ./dev.sh test fast"
            exit 1
        fi

        if [ ! -r "$WORKSPACE/test/regression.out" ]; then
            echo "Error: Cannot read $WORKSPACE/test/regression.out"
            exit 1
        fi

        grep -a -E '^not ok' "$WORKSPACE/test/regression.out" | while read -r test_line; do
            test=$(echo "$test_line" | sed -E 's/not ok[[:space:]]+[0-9]+[[:space:]]+- ([^[:space:]]+).*/\1/')
            if [ -f "$WORKSPACE/test/results/$test.out" ]; then
                echo "Copying results to expected for test: $test"
                safe_update_expected "$WORKSPACE/test/results/$test.out" "$WORKSPACE/test/expected/$test.out"
            else
                echo "Warning: No results file found for test: $test"
            fi
        done
    ;;
    'create-db-structure' )
        eval $(./dev.sh postgres-variables)

        # Restore seed if available — delegates to ./sb which handles
        # exit code semantics (code 1 = warnings, code 2+ = real failure).
        # Intent: pg_restore is ~2 seconds vs running 294 migrations from scratch.
        if [ -f "$WORKSPACE/.db-seed/seed.pg_dump" ]; then
            ./sb db seed restore || {
                echo "Error: Seed restore failed. Consider running:"
                echo "  ./dev.sh recreate-database"
                exit 1
            }
        else
            echo "No seed found in .db-seed/, running all migrations..."
        fi

        # Run migrations
        ./sb migrate up

        # Load secrets after migrations
        JWT_SECRET=$(./sb dotenv -f .env.credentials get JWT_SECRET)
        DEPLOYMENT_SLOT_CODE=$(./sb dotenv -f .env.config get DEPLOYMENT_SLOT_CODE)
        PGDATABASE=statbus_${DEPLOYMENT_SLOT_CODE:-dev}
        ./sb psql -c "INSERT INTO auth.secrets (key, value, description) VALUES ('jwt_secret', '$JWT_SECRET', 'JWT signing secret') ON CONFLICT (key) DO UPDATE SET value = EXCLUDED.value, updated_at = clock_timestamp();"
        ./sb psql -c "ALTER DATABASE $PGDATABASE SET app.settings.deployment_slot_code TO '$DEPLOYMENT_SLOT_CODE';"
      ;;
    'delete-db-structure' )
        ./sb migrate down all
      ;;
    'reset-db-structure' )
        ./sb migrate down all
        ./sb migrate up
        ./sb users create
      ;;
    'create-db' )
        # Start only db, rest, proxy — NOT worker yet (avoids stray tasks from stale procedures)
        ./sb build all_except_app
        docker compose up --detach db proxy rest
        ./dev.sh create-db-structure
        ./sb users create
        # Build the canonical seed (statbus_seed) before the test
        # template, since create-test-template now clones from the
        # seed instead of forking template_statbus + running migrations.
        # Plan section R commit 4.
        ./dev.sh recreate-seed
        ./dev.sh create-test-template
        # Now start worker with clean, fully-migrated DB
        docker compose up --detach worker
      ;;
    'recreate-database' )
        echo "Recreate the backend with the latest database structures"
        ./dev.sh delete-db
        ./dev.sh create-db
      ;;
    'delete-db' )
        ./sb stop all
        # Remove the named Docker volume for PostgreSQL data
        INSTANCE_NAME=$(./sb dotenv -f .env get COMPOSE_INSTANCE_NAME 2>/dev/null || echo "")
        if [ -n "$INSTANCE_NAME" ]; then
          VOLUME_NAME="${INSTANCE_NAME}-db-data"
          if docker volume inspect "$VOLUME_NAME" >/dev/null 2>&1; then
            echo "Removing Docker volume '$VOLUME_NAME'"
            docker volume rm "$VOLUME_NAME"
          fi
        fi
        # Also clean up legacy bind-mount directory if it still exists
        # Owned by postgres (UID 999) — use docker to remove, no sudo needed
        POSTGRES_DIRECTORY="$WORKSPACE/postgres/volumes/db/data"
        if [ -d "$POSTGRES_DIRECTORY" ]; then
          echo "Removing legacy bind-mount directory '$POSTGRES_DIRECTORY'"
          docker run --rm -v "$WORKSPACE/postgres/volumes:/vol" alpine rm -rf /vol/db/data 2>/dev/null \
            || rm -rf "$POSTGRES_DIRECTORY" 2>/dev/null \
            || echo "Warning: could not remove legacy directory (permission denied, may need sudo)"
        fi
      ;;
    'dump-seed' )
        eval $(./dev.sh postgres-variables)

        if ! ./dev.sh is-db-running; then
            echo "Error: Database is not running. Start with: ./sb start all"
            exit 1
        fi

        LATEST_VERSION=$(echo "SELECT version FROM db.migration ORDER BY version DESC LIMIT 1;" \
            | ./sb psql -t -A)

        if [ -z "$LATEST_VERSION" ]; then
            echo "Error: No migrations found in database"
            exit 1
        fi

        SEED_DIR="$WORKSPACE/migrations/seeds"
        SEED_DUMP="$SEED_DIR/schema_${LATEST_VERSION}.pg_dump"
        SEED_LIST="$SEED_DIR/schema_${LATEST_VERSION}.pg_list"
        mkdir -p "$SEED_DIR"

        echo "Creating seed for migration version $LATEST_VERSION..."
        docker compose exec -T db pg_dump -U postgres \
            -Fc \
            --no-owner \
            "$PGDATABASE" > "$SEED_DUMP"

        echo "Seed dump created: $SEED_DUMP"
        ls -lh "$SEED_DUMP"

        docker compose cp "$SEED_DUMP" db:/tmp/seed.pg_dump
        docker compose exec -T db pg_restore -l /tmp/seed.pg_dump > "$SEED_LIST"
        docker compose exec -T db rm -f /tmp/seed.pg_dump

        echo "Seed list created: $SEED_LIST"
        echo "Edit this file to comment out items that cause restore issues."
      ;;
    'list-seeds' )
        SEED_DIR="$WORKSPACE/migrations/seeds"
        echo "Available seeds in $SEED_DIR:"
        ls -lh "$SEED_DIR"/*.pg_dump 2>/dev/null || echo "  (none - run 'dump-seed' to create one)"

        LIST_FILES=$(ls "$SEED_DIR"/*.pg_list 2>/dev/null)
        if [ -n "$LIST_FILES" ]; then
            echo ""
            echo "List files (edit these to customize restore):"
            ls -lh "$SEED_DIR"/*.pg_list
        fi

        if ./dev.sh is-db-running 2>/dev/null; then
            LATEST_DB_VERSION=$(echo "SELECT version FROM db.migration ORDER BY version DESC LIMIT 1;" \
                | ./sb psql -t -A 2>/dev/null)
            echo ""
            echo "Current database migration version: ${LATEST_DB_VERSION:-not available}"
        fi
      ;;
    'clean-test-databases' )
        eval $(./dev.sh postgres-variables)

        echo "Finding test databases to clean up..."
        TEST_DBS=$(./sb psql -d postgres -t -A -c "
            SELECT datname FROM pg_database
            WHERE datname LIKE 'test_%'
            ORDER BY datname;
        ")

        if [ -z "$TEST_DBS" ]; then
            echo "No test databases found."
            exit 0
        fi

        echo "Found test databases:"
        echo "$TEST_DBS" | sed 's/^/  /'

        if [ "${1:-}" != "--force" ]; then
            echo ""
            read -p "Drop all these databases? [y/N] " -r < "$TTY_INPUT"
            if [[ ! $REPLY =~ ^[Yy]$ ]]; then
                echo "Cancelled."
                exit 0
            fi
        fi

        FAILED_DBS=""
        DROPPED_COUNT=0
        while read -r db; do
            if [ -n "$db" ]; then
                echo "Dropping: $db"
                if ./sb psql -d postgres -c "DROP DATABASE IF EXISTS \"$db\";" 2>&1; then
                    DROPPED_COUNT=$((DROPPED_COUNT + 1))
                else
                    echo "  Warning: Failed to drop $db (may have active connections)"
                    FAILED_DBS="$FAILED_DBS $db"
                fi
            fi
        done <<< "$TEST_DBS"

        echo ""
        echo "Cleanup complete: $DROPPED_COUNT databases dropped."
        if [ -n "$FAILED_DBS" ]; then
            echo "Warning: Could not drop:$FAILED_DBS"
            echo "These may have active connections. Try stopping services first."
            exit 1
        fi
      ;;
    'create-test-template' )
        eval $(./dev.sh postgres-variables)
        TEMPLATE_NAME="${POSTGRES_TEST_DB:-statbus_test_template}"
        SEED_NAME="${POSTGRES_SEED_DB:-statbus_seed}"

        # Per plan section R commit 4: build the test template by
        # cloning the canonical seed (POSTGRES_SEED_DB) — NOT by
        # forking template_statbus + restoring the published artifact
        # + running migrate up. The seed is already at HEAD; clone is
        # a millisecond-scale CREATE DATABASE WITH TEMPLATE.
        #
        # Pre-condition: seed must exist and be at HEAD. Operator
        # bootstraps via `./dev.sh recreate-seed` (or composite
        # `./dev.sh migrate-and-test fast`).

        SEED_EXISTS=$(./sb psql -d postgres -t -A -c \
            "SELECT 1 FROM pg_database WHERE datname = '$SEED_NAME';" 2>/dev/null || echo "0")
        if [ "$SEED_EXISTS" != "1" ]; then
            echo "Error: seed database '$SEED_NAME' does not exist."
            echo "  Build it: ./dev.sh recreate-seed"
            echo "  Or run end-to-end: ./dev.sh migrate-and-test fast"
            exit 1
        fi

        echo "Creating test template by cloning seed: $SEED_NAME -> $TEMPLATE_NAME"

        TEMPLATE_EXISTS=$(./sb psql -d postgres -t -A -c \
            "SELECT 1 FROM pg_database WHERE datname = '$TEMPLATE_NAME';" 2>/dev/null || echo "0")
        if [ "$TEMPLATE_EXISTS" = "1" ]; then
            echo "Existing template found, removing it..."
        fi

        # STATBUS-141: drop + recreate under DB advisory lock 59328 — the SAME
        # lock template CONSUMERS hold while cloning (generate-types, dev.sh
        # ~1883: SELECT pg_advisory_lock(59328); ... CREATE DATABASE ... WITH
        # TEMPLATE ...; SELECT pg_advisory_unlock(59328); one psql session).
        # Without this, a rebuild could drop the template out from under a
        # consumer's mid-clone (133 review finding). 59328 is SESSION-scoped
        # (pg_advisory_lock, no xact variant here), so the drop and the
        # recreate must run as ONE held psql session — lock first statement,
        # unlock last — rather than delegating to `./dev.sh seed-clone` (a
        # separate ./sb invocation opens a separate connection and would lose
        # the lock); seed-clone's own CREATE DATABASE ... WITH TEMPLATE ...
        # OWNER postgres statement is mirrored inline for that reason. Each
        # drop step is idempotent (terminate/unmark/drop-if-exists) so this
        # runs safely whether or not a prior template existed.
        if ! ./sb psql -d postgres -v ON_ERROR_STOP=1 <<EOF
            SELECT pg_advisory_lock(59328);
            SELECT pg_terminate_backend(pid) FROM pg_stat_activity WHERE datname = '$TEMPLATE_NAME';
            UPDATE pg_database SET datistemplate = false WHERE datname = '$TEMPLATE_NAME';
            DROP DATABASE IF EXISTS $TEMPLATE_NAME;
            SELECT pg_terminate_backend(pid) FROM pg_stat_activity WHERE datname = '$SEED_NAME';
            -- STATBUS-141 keep-in-sync: mirrors the 'seed-clone' case's own
            -- CREATE DATABASE statement (dev.sh ~1730). Kept inline, not called
            -- as that subprocess, because 59328 is session-scoped and the
            -- middle roads both fail: seed-clone taking the lock itself would
            -- deadlock under this already-holding session; releasing here and
            -- letting seed-clone re-acquire would reopen the drop-to-create gap
            -- this fix exists to close. Update BOTH sites together if this
            -- statement ever changes.
            CREATE DATABASE $TEMPLATE_NAME WITH TEMPLATE $SEED_NAME OWNER postgres;
            SELECT pg_advisory_unlock(59328);
EOF
        then
            echo "Error: Failed to drop/recreate test template under advisory lock 59328."
            echo "There may be active connections. Check with:"
            echo "  ./sb psql -c \"SELECT * FROM pg_stat_activity WHERE datname = '$TEMPLATE_NAME';\""
            exit 1
        fi

        # Load JWT secret so auth works in tests. Seed excludes
        # auth.secrets data (security hard-rule); each consumer
        # injects its own JWT. Same as pre-rc.66 behavior.
        JWT_SECRET=$(./sb dotenv -f .env.credentials get JWT_SECRET)
        ./sb psql -d $TEMPLATE_NAME -c \
            "INSERT INTO auth.secrets (key, value, description) VALUES ('jwt_secret', '$JWT_SECRET', 'JWT signing secret') ON CONFLICT (key) DO UPDATE SET value = EXCLUDED.value, updated_at = clock_timestamp();"

        if ! ./sb psql -d postgres -c "
            ALTER DATABASE $TEMPLATE_NAME WITH IS_TEMPLATE = true;
            ALTER DATABASE $TEMPLATE_NAME WITH ALLOW_CONNECTIONS = false;
        "; then
            echo "Error: Template created but failed to mark as template."
            echo "This may cause issues with test isolation. Check database permissions."
            exit 1
        fi

        echo "Template created: $TEMPLATE_NAME (cloned from $SEED_NAME)"

        # STATBUS-126: the staleness stamp keys on the migration CONTENT
        # fingerprint (`./sb migrate fingerprint` — cli/internal/migrate/
        # fingerprint.go's UpMigrationsFingerprintUpTo, the SAME lister
        # STATBUS-138/116 already share), NOT the max migration TIMESTAMP.
        # A timestamp stamp is blind to editing an ALREADY-applied migration's
        # bytes (STATBUS-124: the architect appended fixes to an applied
        # migration, the timestamp stamp still matched, and a stale template
        # silently reproduced the pre-fix diff — a false "fix didn't work").
        # The content fingerprint changes on ANY byte edit anywhere in
        # migrations/, so that class can't recur; an unchanged migrations/
        # directory still fingerprints identically (no rebuild-every-run).
        #
        # The stamp is the WHOLE on-disk set's fingerprint (no version bound)
        # — simpler than bounding it to the seed's own version, and correct
        # for this stamp's actual job: "would re-running create-test-template
        # right now reproduce a BYTE-IDENTICAL template" — which the seed's
        # own staleness (tracked separately below, unchanged) doesn't affect.
        if [ ! -x ./sb ] || ! ./sb --version >/dev/null 2>&1; then
            echo "Error: ./sb is missing or not runnable — cannot compute the migration content fingerprint." >&2
            echo "  Build it first: ./dev.sh cross-build-sb (or: cd cli && go build -o ../sb .)" >&2
            echo "  Refusing to write a stamp without it — a stale/placeholder stamp would let a" >&2
            echo "  later run silently reuse this template even after migrations/ content changes." >&2
            exit 1
        fi
        FINGERPRINT=$(./sb migrate fingerprint) || { echo "Error: ./sb migrate fingerprint failed." >&2; exit 1; }

        SEED_VERSION=$(./sb psql -d "$SEED_NAME" -t -A -c \
            "SELECT max(version) FROM db.migration;" 2>/dev/null | tr -d '[:space:]')
        # On-disk HEAD — used ONLY for the stale-seed diagnostic below.
        LATEST_MIGRATION=$(for f in "$WORKSPACE/migrations/"*.up.sql "$WORKSPACE/migrations/"*.up.psql; do
            [ -e "$f" ] || continue
            basename "$f" | cut -d_ -f1
        done | sort | tail -1)
        if [ -n "$SEED_VERSION" ]; then
            mkdir -p "$WORKSPACE/tmp"
            echo "$FINGERPRINT" > "$WORKSPACE/tmp/test-template-migrations-sha"
            echo "Test template migration stamp recorded: $FINGERPRINT (content fingerprint via ./sb migrate fingerprint; cloned seed version $SEED_VERSION)"
            if [ -n "$LATEST_MIGRATION" ] && [ "$SEED_VERSION" -lt "$LATEST_MIGRATION" ]; then
                echo "WARNING: cloned a STALE seed ($SEED_VERSION) — on-disk HEAD is $LATEST_MIGRATION."
                echo "         The test template is BEHIND HEAD. Bring the seed to HEAD first:"
                echo "           ./dev.sh recreate-seed      (or: ./sb migrate up --target seed)"
                echo "         then re-run: ./dev.sh create-test-template"
            fi
        else
            echo "Warning: could not read migration version from seed '$SEED_NAME'; template stamp not written."
        fi
      ;;
    # ── Seed lifecycle primitives (plan section R, commit 3/4) ─────
    # Each does ONE thing — no auto-rebuild magic. Composition is
    # explicit (recreate-seed = delete + create + migrate; that's the
    # only convenience wrapper). Operators run primitives directly when
    # they need finer control, or use the wrapper for the common case.
    #
    # The seed DB is build-time-only: never worker-active, never
    # contains app data, never written to by ./sb commands other than
    # `migrate up --target seed` and these primitives. Source of the
    # `./sb db seed dump` that CI bakes into the statbus-seed image.
    'create-seed' )
        # Delegates to the Go single source of truth (cli/cmd/seed.go
        # CreateSeedDb) — lifted there so the hermetic seed-builder image and
        # dev share ONE definition of "create the seed DB from template_statbus
        # + auth grants" (was ~50 lines of psql here; zero drift now).
        ./sb db seed create-db || exit $?
      ;;
    'delete-seed' )
        eval $(./dev.sh postgres-variables)
        SEED_NAME="${POSTGRES_SEED_DB:-statbus_seed}"

        SEED_EXISTS=$(./sb psql -d postgres -t -A -c \
            "SELECT 1 FROM pg_database WHERE datname = '$SEED_NAME';" 2>/dev/null || echo "0")
        if [ "$SEED_EXISTS" != "1" ]; then
            echo "Seed database '$SEED_NAME' does not exist; nothing to delete."
            exit 0
        fi

        ./sb psql -d postgres -c "
            SELECT pg_terminate_backend(pid)
            FROM pg_stat_activity
            WHERE datname = '$SEED_NAME';
        " || true

        if ! ./sb psql -d postgres -c "DROP DATABASE $SEED_NAME;"; then
            echo "Error: Failed to drop seed database $SEED_NAME."
            exit 1
        fi
        echo "Seed database dropped: $SEED_NAME"
      ;;
    'recreate-seed' )
        # acquire EXCLUSIVE statbus_seed mutation
        # lock so concurrent readers (./sb types generate via
        # assert-db-at-head, ./dev.sh generate-doc-db, etc.)
        # block during this body's DROP/CREATE/migrate.Up sequence
        # instead of hitting statbus_seed mid-rebuild with a confusing
        # "database does not exist" error. The lock is held on a
        # connection to the postgres system DB so it survives
        # DROP DATABASE statbus_seed.
        #
        # Re-exec self under `./sb db with-seed-lock --exclusive` so
        # the lock is held for the full duration of the body. The
        # STATBUS_SEED_LOCK_HELD env var prevents recursive re-wrapping
        # when the body internally re-execs (the FULL_REPLAY fallbacks
        # below do exactly that).
        if [ "${STATBUS_SEED_LOCK_HELD:-0}" != "1" ]; then
            exec ./sb db with-seed-lock --exclusive -- env STATBUS_SEED_LOCK_HELD=1 "$0" recreate-seed
        fi

        # Rebuild ${POSTGRES_SEED_DB} from the latest published seed artifact
        # (the statbus-seed:<commit_short> image via ./sb db seed fetch), then
        # apply only the migrations newer than the artifact's recorded migration_version.
        #
        # Why not always migrate-from-zero: applying ~348 migrations from an
        # empty schema is ~1-3 minutes; pg_restore of the artifact is ~2s
        # and incremental `./sb migrate up --target seed` is ~50ms per
        # pending migration. Typical dev workflow (1-10 new migrations per
        # pull): 5-20× faster than from-zero.
        #
        # The artifact-restore + incremental path is functionally equivalent
        # to from-zero migrations — `./sb migrate up` reads `db.migration`
        # to know what's applied and only runs pending. eagerContentHashCheck
        # in migrate.runUp catches drift between already-applied migration
        # rows and on-disk file bytes, so silent corruption of the chain
        # surfaces loudly.
        #
        # Operator overrides:
        #   FULL_REPLAY=1            — bypass the artifact entirely; rebuild
        #                              from-zero. Use when debugging the
        #                              "is this bug because of a partial
        #                              migration?" class of question.
        #   STATBUS_DB_SEED_NO_FETCH=1 — skip the `./sb db seed fetch` round
        #                              trip. Use offline or in CI where the
        #                              artifact is pre-staged.
        #
        # Automatic fallback to FULL_REPLAY fires when:
        #   - fetch fails AND no cached artifact at .db-seed/seed.pg_dump
        #   - artifact's migration_version > local on-disk max (means local
        #     working tree is older than the artifact — confusing state,
        #     safer to rebuild from on-disk migrations)
        #   - pg_restore exits non-zero with a real failure (warnings — exit
        #     code 1 from --clean drops — are handled by ./sb db seed restore)
        #
        # Migration 20260427124351 self-drains has_pending residual via an
        # inline CALL worker.process_tasks() in its body — no separate drain
        # step needed here. The auto-rebuild in cli/internal/migrate/migrate.go
        # fires after Up() succeeds and clones the (now-clean) seed into the
        # test template.
        eval $(./dev.sh postgres-variables)
        SEED_NAME="${POSTGRES_SEED_DB:-statbus_seed}"

        if [ "${FULL_REPLAY:-0}" = "1" ]; then
            echo "recreate-seed: FULL_REPLAY=1 — rebuilding $SEED_NAME from zero via all migrations."
            ./dev.sh delete-seed
            ./dev.sh create-seed
            ./sb migrate up --target seed --verbose
            exit 0
        fi

        # Always auto-fetch unless operator opts out. Cheap (~100ms) and
        # picks up seeds published by other operators / CI on origin.
        if [ "${STATBUS_DB_SEED_NO_FETCH:-0}" != "1" ]; then
            echo "recreate-seed: fetching seed from the statbus-seed image..."
            if ! ./sb db seed fetch; then
                if [ ! -f "$WORKSPACE/.db-seed/seed.pg_dump" ]; then
                    echo "recreate-seed: fetch failed and no cached artifact — falling back to FULL_REPLAY."
                    FULL_REPLAY=1 exec "$0" recreate-seed
                fi
                echo "recreate-seed: fetch failed; will use cached artifact at .db-seed/seed.pg_dump."
            fi
        fi

        if [ ! -f "$WORKSPACE/.db-seed/seed.pg_dump" ]; then
            echo "recreate-seed: no artifact available (STATBUS_DB_SEED_NO_FETCH=$STATBUS_DB_SEED_NO_FETCH, file absent) — falling back to FULL_REPLAY."
            FULL_REPLAY=1 exec "$0" recreate-seed
        fi

        # Guard against artifact-ahead-of-working-tree: if the artifact's
        # migration_version > the highest local on-disk migration, the
        # operator's working tree is older than the published artifact
        # (e.g. git-switched to a feature branch with the artifact still
        # cached from master). pg_restore would land schema the local
        # migrations don't acknowledge — confusing state. Drop to
        # FULL_REPLAY which is grounded in local migrations only.
        ARTIFACT_VERSION=$(awk -F'"' '/"migration_version"/ {print $4}' "$WORKSPACE/.db-seed/seed.json" 2>/dev/null || echo "")
        LATEST_LOCAL_MIGRATION=$(for f in "$WORKSPACE/migrations/"*.up.sql "$WORKSPACE/migrations/"*.up.psql; do
            [ -e "$f" ] || continue
            basename "$f" | cut -d_ -f1
        done | sort | tail -1)
        if [ -n "$ARTIFACT_VERSION" ] && [ -n "$LATEST_LOCAL_MIGRATION" ] && [ "$ARTIFACT_VERSION" \> "$LATEST_LOCAL_MIGRATION" ]; then
            echo "recreate-seed: artifact version $ARTIFACT_VERSION is ahead of local on-disk max $LATEST_LOCAL_MIGRATION — falling back to FULL_REPLAY."
            FULL_REPLAY=1 exec "$0" recreate-seed
        fi

        # Diagnostic: show what we're starting from. Output goes to operator
        # log so reviewers can see the artifact version baseline.
        ./sb db seed status || true

        ./dev.sh delete-seed
        ./dev.sh create-seed

        if ! ./sb db seed restore --database "$SEED_NAME"; then
            echo "recreate-seed: restore failed — falling back to FULL_REPLAY."
            FULL_REPLAY=1 exec "$0" recreate-seed
        fi

        # Incremental: migrate up consults db.migration to apply only
        # migrations whose version isn't already recorded. Typical run
        # applies just the few migrations newer than the artifact.
        #
        # STATBUS-156: exit 21 (migrate.ExitStaleRestoredMigration) is a
        # DISTINCT, dedicated signal — never inferred from stderr text — that
        # this cached seed predates a legitimately merged retroactive fix to
        # an already-released migration (the restored ledger disagrees with a
        # migration file that is otherwise clean, i.e. no live local edit).
        # That is not the operator's fault and not recoverable by editing
        # anything; the honest fix is to discard the stale cache and rebuild
        # full. A genuine local edit to a released migration still hits the
        # ordinary immutability refusal below (exit 1), unchanged.
        set +e
        MIGRATE_UP_OUT=$(./sb migrate up --target seed --verbose 2>&1)
        MIGRATE_UP_RC=$?
        set -e
        echo "$MIGRATE_UP_OUT"
        if [ "$MIGRATE_UP_RC" -eq 21 ]; then
            echo "recreate-seed: cached seed predates a merged edit to a migration — replaying from scratch."
            FULL_REPLAY=1 exec "$0" recreate-seed
        elif [ "$MIGRATE_UP_RC" -ne 0 ]; then
            exit "$MIGRATE_UP_RC"
        fi
      ;;
    'seed-status' )
        eval $(./dev.sh postgres-variables)
        SEED_NAME="${POSTGRES_SEED_DB:-statbus_seed}"

        SEED_EXISTS=$(./sb psql -d postgres -t -A -c \
            "SELECT 1 FROM pg_database WHERE datname = '$SEED_NAME';" 2>/dev/null || echo "0")
        if [ "$SEED_EXISTS" != "1" ]; then
            echo "Status: missing"
            echo "  Seed database '$SEED_NAME' does not exist."
            echo "  Bootstrap: ./dev.sh recreate-seed"
            exit 1
        fi

        # Set comparison: db.migration rows vs migrations/*.up.{sql,psql}
        # at HEAD. Asymmetric reporting (missing|behind|ahead|mismatch|
        # in sync) per plan section R. Detects git revert / branch-switch
        # scenarios that a max-version-only check would miss.
        DB_VERSIONS=$(./sb psql -d "$SEED_NAME" -t -A -c \
            "SELECT version FROM db.migration ORDER BY version" 2>/dev/null | sort -u)
        FS_VERSIONS=$(for f in "$WORKSPACE/migrations/"*.up.sql "$WORKSPACE/migrations/"*.up.psql; do
            [ -e "$f" ] || continue
            basename "$f" | cut -d_ -f1
        done | sort -u)

        BEHIND=$(comm -13 <(echo "$DB_VERSIONS") <(echo "$FS_VERSIONS"))   # in HEAD, not in DB
        AHEAD=$(comm -23 <(echo "$DB_VERSIONS") <(echo "$FS_VERSIONS"))    # in DB, not in HEAD
        # `grep -c .` exits 1 when there are no matches (empty BEHIND/AHEAD).
        # With `set -euo pipefail` (line 9) that exit aborts the script before
        # we reach the in-sync branch. `|| true` keeps the count = "0" path alive.
        BEHIND_N=$(echo -n "$BEHIND" | grep -c . || true)
        AHEAD_N=$(echo -n "$AHEAD" | grep -c . || true)

        if [ "$BEHIND_N" -eq 0 ] && [ "$AHEAD_N" -eq 0 ]; then
            echo "Status: in sync"
            echo "  Seed at version $(echo "$DB_VERSIONS" | tail -1) matches HEAD."
            exit 0
        fi
        if [ "$BEHIND_N" -gt 0 ] && [ "$AHEAD_N" -eq 0 ]; then
            echo "Status: behind by $BEHIND_N migration(s)"
            echo "$BEHIND" | sed 's/^/  + /'
            echo "  Apply pending migrations: ./sb migrate up --target seed"
            exit 1
        fi
        if [ "$BEHIND_N" -eq 0 ] && [ "$AHEAD_N" -gt 0 ]; then
            echo "Status: ahead by $AHEAD_N migration(s)"
            echo "$AHEAD" | sed 's/^/  - /'
            echo "  Rebuild from HEAD: ./dev.sh recreate-seed"
            exit 1
        fi
        echo "Status: mismatch ($BEHIND_N missing, $AHEAD_N orphan)"
        echo "  Missing in seed (in HEAD, not applied):"
        echo "$BEHIND" | sed 's/^/    + /'
        echo "  Orphan in seed (applied, not in HEAD):"
        echo "$AHEAD" | sed 's/^/    - /'
        echo "  Rebuild from HEAD: ./dev.sh recreate-seed"
        exit 1
      ;;
    'seed-clone' )
        # Clone ${POSTGRES_SEED_DB} into the named target DB. Used by
        # commit 4's create-test-template retarget; exposed as a
        # primitive so other consumers (cross-machine bootstrap, dev
        # convenience) can compose on top.
        eval $(./dev.sh postgres-variables)
        SEED_NAME="${POSTGRES_SEED_DB:-statbus_seed}"

        TARGET_NAME="${1:-}"
        if [ -z "$TARGET_NAME" ]; then
            echo "Error: ./dev.sh seed-clone <target_db> requires a target name."
            echo "  Example: ./dev.sh seed-clone statbus_test_template"
            exit 1
        fi

        SEED_EXISTS=$(./sb psql -d postgres -t -A -c \
            "SELECT 1 FROM pg_database WHERE datname = '$SEED_NAME';" 2>/dev/null || echo "0")
        if [ "$SEED_EXISTS" != "1" ]; then
            echo "Error: seed database '$SEED_NAME' does not exist."
            echo "  Bootstrap: ./dev.sh recreate-seed"
            exit 1
        fi

        TARGET_EXISTS=$(./sb psql -d postgres -t -A -c \
            "SELECT 1 FROM pg_database WHERE datname = '$TARGET_NAME';" 2>/dev/null || echo "0")
        if [ "$TARGET_EXISTS" = "1" ]; then
            echo "Error: target database '$TARGET_NAME' already exists. Drop it first."
            exit 1
        fi

        # Postgres CREATE DATABASE WITH TEMPLATE requires the source DB
        # to have no active connections. Terminate any stragglers (the
        # seed should never have any but be defensive).
        ./sb psql -d postgres -c "
            SELECT pg_terminate_backend(pid)
            FROM pg_stat_activity
            WHERE datname = '$SEED_NAME';
        " || true

        # STATBUS-141 keep-in-sync: the 'create-test-template' case inlines this
        # exact statement (dev.sh ~1411, under advisory lock 59328) rather than
        # calling this subprocess, because 59328 is session-scoped and calling
        # out here would either deadlock (if this case also took the lock) or
        # reopen the drop-to-create gap (if it re-acquired after a release).
        # Update BOTH sites together if this statement ever changes.
        if ! ./sb psql -d postgres -c "
            CREATE DATABASE $TARGET_NAME WITH TEMPLATE $SEED_NAME OWNER postgres;
        "; then
            echo "Error: Failed to clone $SEED_NAME -> $TARGET_NAME."
            exit 1
        fi
        echo "Seed cloned: $SEED_NAME -> $TARGET_NAME"
      ;;
    'test-isolated' )
        eval $(./dev.sh postgres-variables)
        TEMPLATE_NAME="${POSTGRES_TEST_DB:-statbus_test_template}"

        TEST_NAME="${1:-}"
        shift || true
        UPDATE_EXPECTED=false
        for arg in "$@"; do
            if [ "$arg" = "--update-expected" ]; then
                UPDATE_EXPECTED=true
            fi
        done

        if [ -z "$TEST_NAME" ]; then
            echo "Error: Test name required"
            echo "Usage: ./dev.sh test-isolated <test_name> [--update-expected]"
            exit 1
        fi

        if [ "$TEST_NAME" = "all" ] || [ "$TEST_NAME" = "fast" ] || [ "$TEST_NAME" = "failed" ]; then
            echo "Error: '$TEST_NAME' is a test group, not an individual test."
            echo "Use './dev.sh test $TEST_NAME' to run test groups."
            exit 1
        fi

        PG_REGRESS_DIR="$WORKSPACE/test"
        if [ ! -f "$PG_REGRESS_DIR/sql/$TEST_NAME.sql" ]; then
            echo "Error: Test '$TEST_NAME' not found."
            echo ""
            echo "Available tests:"
            basename -s .sql "$PG_REGRESS_DIR/sql"/*.sql | sed 's/^/  /'
            exit 1
        fi

        SAFE_TEST_NAME=$(echo "$TEST_NAME" | tr -cd '[:alnum:]_')
        TEST_DB="test_${SAFE_TEST_NAME}_$$"

        POSTGRESQL_MAJOR=$(grep -E "^ARG postgresql_major=" "$WORKSPACE/postgres/Dockerfile" | cut -d= -f2)
        PG_REGRESS="/usr/lib/postgresql/$POSTGRESQL_MAJOR/lib/pgxs/src/test/regress/pg_regress"
        CONTAINER_REGRESS_DIR="/statbus/test"

        if ! ./sb psql -d postgres -t -A -c "SELECT 1 FROM pg_database WHERE datname = '$TEMPLATE_NAME';" 2>/dev/null | grep -q 1; then
            echo "Error: Template database '$TEMPLATE_NAME' not found."
            echo "Run './dev.sh create-db' or './dev.sh create-test-template' first."
            exit 1
        fi

        echo "=== Running isolated test: $TEST_NAME ==="
        echo "Creating isolated test database: $TEST_DB from template $TEMPLATE_NAME"

        LOG_CAPTURE_PID=""
        DB_LOG_FILE=""
        cleanup_test_db() {
            local exit_code=$?
            # This trap replaced the acquire-time release trap, so release the
            # test-run lock here too (idempotent; no-op if we don't own it, e.g.
            # when test-isolated runs as a child of `test`).
            release_test_run_lock
            if [ -n "$LOG_CAPTURE_PID" ]; then
                kill "$LOG_CAPTURE_PID" 2>/dev/null || true
                wait "$LOG_CAPTURE_PID" 2>/dev/null || true
                if [ -f "$DB_LOG_FILE" ]; then
                    LOG_LINE_COUNT=$(wc -l < "$DB_LOG_FILE" | tr -d ' ')
                    echo "DEBUG=true: Database logs saved to: $DB_LOG_FILE ($LOG_LINE_COUNT lines)"
                fi
            fi
            if [ "${PERSIST:-false}" = "true" ]; then
                echo "PERSIST=true: Keeping test database: $TEST_DB"
                return $exit_code
            fi
            if [ -n "$TEST_DB" ]; then
                echo "Cleaning up test database: $TEST_DB"
                if ! ./sb psql -d postgres -c "DROP DATABASE IF EXISTS \"$TEST_DB\";" 2>&1; then
                    echo "Warning: Failed to drop test database '$TEST_DB'"
                fi
            fi
            return $exit_code
        }
        trap cleanup_test_db EXIT

        if ! ./sb psql -d postgres -v ON_ERROR_STOP=1 <<EOF
            SELECT pg_advisory_lock(59328);
            ALTER DATABASE $TEMPLATE_NAME WITH ALLOW_CONNECTIONS = true;
            CREATE DATABASE "$TEST_DB" WITH TEMPLATE $TEMPLATE_NAME;
            ALTER DATABASE $TEMPLATE_NAME WITH ALLOW_CONNECTIONS = false;
            SELECT pg_advisory_unlock(59328);
EOF
        then
            echo "Error: Failed to create test database from template"
            exit 1
        fi

        debug_arg=""
        if [ "${DEBUG:-}" = "true" ]; then
            debug_arg="--debug"
            DB_LOG_FILE="$WORKSPACE/tmp/db-logs-${TEST_NAME}-$$.log"
            echo "DEBUG=true: Capturing database logs to: $DB_LOG_FILE"
            docker compose logs db --follow --since 0s > "$DB_LOG_FILE" 2>&1 &
            LOG_CAPTURE_PID=$!
        fi

        expected_file="$PG_REGRESS_DIR/expected/$TEST_NAME.out"
        if [ ! -f "$expected_file" ] && [ -f "$PG_REGRESS_DIR/sql/$TEST_NAME.sql" ]; then
            echo "Warning: Expected output file $expected_file not found. Creating an empty placeholder."
            touch "$expected_file"
        fi

        TEST_EXIT_CODE=0
        docker compose exec --workdir "/statbus" db \
            $PG_REGRESS $debug_arg \
            --use-existing \
            --bindir="/usr/lib/postgresql/$POSTGRESQL_MAJOR/bin" \
            --inputdir=$CONTAINER_REGRESS_DIR \
            --outputdir=$CONTAINER_REGRESS_DIR \
            --dbname="$TEST_DB" \
            --user=$PGUSER \
            "$TEST_NAME" || TEST_EXIT_CODE=$?

        # STATBUS-158 AC#2: an embedded NUL is never a legitimate test
        # failure — check regardless of pass/fail above. Also covers the
        # `./dev.sh test` shared-tests action's isolated-tests loop, which
        # runs each test through this same test-isolated action as a child
        # process.
        check_results_for_nul_corruption "$PG_REGRESS_DIR" "$TEST_NAME" || TEST_EXIT_CODE=1

        if [ -n "$LOG_CAPTURE_PID" ]; then
            kill "$LOG_CAPTURE_PID" 2>/dev/null || true
            wait "$LOG_CAPTURE_PID" 2>/dev/null || true
            LOG_CAPTURE_PID=""
            if [ -f "$DB_LOG_FILE" ]; then
                LOG_LINE_COUNT=$(wc -l < "$DB_LOG_FILE" | tr -d ' ')
                echo "DEBUG=true: Database logs saved to: $DB_LOG_FILE ($LOG_LINE_COUNT lines)"
                echo "  Tip: Search for slow queries with: grep 'duration: [0-9]\\{4,\\}' $DB_LOG_FILE"
            fi
        fi

        if [ "$UPDATE_EXPECTED" = "true" ]; then
            result_file="$PG_REGRESS_DIR/results/$TEST_NAME.out"
            if [ -f "$result_file" ]; then
                echo "  -> Updating expected output for $TEST_NAME"
                cp "$result_file" "$expected_file"
            fi
        fi

        exit $TEST_EXIT_CODE
      ;;
     'generate-types' )
        TEMPLATE_NAME="${POSTGRES_TEST_DB:-statbus_test_template}"
        TYPES_DB="statbus_types_gen_$$"

        TEMPLATE_EXISTS=$(./sb psql -d postgres -t -A -c \
            "SELECT 1 FROM pg_database WHERE datname = '$TEMPLATE_NAME';" 2>/dev/null || echo "0")
        if [ "$TEMPLATE_EXISTS" != "1" ]; then
            echo "Error: Template database '$TEMPLATE_NAME' not found."
            echo "Create it with: ./dev.sh create-test-template"
            exit 1
        fi

        echo "Creating temporary types database: $TYPES_DB from $TEMPLATE_NAME"
        ./sb psql -d postgres -v ON_ERROR_STOP=1 <<EOF
            SELECT pg_advisory_lock(59328);
            ALTER DATABASE $TEMPLATE_NAME WITH ALLOW_CONNECTIONS = true;
            CREATE DATABASE "$TYPES_DB" WITH TEMPLATE $TEMPLATE_NAME;
            ALTER DATABASE $TEMPLATE_NAME WITH ALLOW_CONNECTIONS = false;
            SELECT pg_advisory_unlock(59328);
EOF

        cleanup_types_db() {
            local exit_code=$?
            echo "Cleaning up types database: $TYPES_DB"
            ./sb psql -d postgres -c "DROP DATABASE IF EXISTS \"$TYPES_DB\";" 2>/dev/null || true
            return $exit_code
        }
        trap cleanup_types_db EXIT

        POSTGRES_APP_DB="$TYPES_DB" ./sb types generate
      ;;
    'generate-doc-db' )
        set +e
        check_stamp_guard "./dev.sh generate-doc-db" "db-docs-passed-sha" "migrations"
        guard_rc=$?
        set -e
        case $guard_rc in
            0) DOCDB_STAMP_WITHHELD=0 ;;
            1) exit 0 ;;
            3) DOCDB_STAMP_WITHHELD=1 ;;  # RUN_NO_STAMP: regenerate, withhold the stamp (dirty tree)
            # STATBUS-079: fail-fast on any rc outside the guard's 0/1/3 contract
            # (silent fall-through → DOCDB_STAMP_WITHHELD unset → dirty stamp written).
            *) echo "check_stamp_guard: unexpected rc $guard_rc" >&2; exit 1 ;;
        esac

        TEMPLATE_NAME="${POSTGRES_TEST_DB:-statbus_test_template}"
        DOC_DB="statbus_doc_gen_$$"

        # Refuse if the SEED's db.migration doesn't match HEAD's on-disk
        # migrations (the correction: assert against the seed, the
        # canonical source-of-truth, NOT the test_template). The
        # test_template is downstream of the seed (clone-via-CREATE WITH
        # TEMPLATE) and is intentionally non-connectable so per-test
        # clones go fast; querying it directly silently returned empty
        # stdout in the original wiring, producing a false "BEHIND HEAD"
        # diagnostic. The template's freshness relative to the seed is
        # policed by migrate-and-test fast via the
        # tmp/test-template-migrations-sha stamp check.
        #
        # Without this gate a stale seed would produce doc/db/*.md
        # reflecting an older schema; the stamp would still pass the
        # basic SHA check (line 1) but the H1 two-line stamp's line 2
        # (source-DB migration_version) would catch the bypass at
        # preflight time. Both layers defend the same property.
        #
        # migrated from the bash assert_db_at_head
        # function to the Go subcommand `./sb assert-db-at-head`, which
        # internally acquires a SHARED advisory lock on the
        # statbus_seed mutation key. On success, the subcommand echoes
        # the seed's max migration version on stdout; capture it for
        # the H1 two-line stamp write below.
        SEED_NAME_DOC="${POSTGRES_SEED_DB:-statbus_seed}"
        SOURCE_VERSION=$(./sb assert-db-at-head "$SEED_NAME_DOC" "./dev.sh generate-doc-db") || exit 1

        echo "Creating temporary documentation database: $DOC_DB from $TEMPLATE_NAME"
        ./sb psql -d postgres -v ON_ERROR_STOP=1 <<EOF
            SELECT pg_advisory_lock(59328);
            ALTER DATABASE $TEMPLATE_NAME WITH ALLOW_CONNECTIONS = true;
            CREATE DATABASE "$DOC_DB" WITH TEMPLATE $TEMPLATE_NAME;
            ALTER DATABASE $TEMPLATE_NAME WITH ALLOW_CONNECTIONS = false;
            SELECT pg_advisory_unlock(59328);
EOF

        cleanup_doc_db() {
            local exit_code=$?
            echo "Cleaning up documentation database: $DOC_DB"
            ./sb psql -d postgres -c "DROP DATABASE IF EXISTS \"$DOC_DB\";" 2>/dev/null || true
            return $exit_code
        }
        trap cleanup_doc_db EXIT

        doc_psql() {
            ./sb psql -d "$DOC_DB" "$@"
        }

        mkdir -p doc/db/table doc/db/view doc/db/function
        echo "Cleaning documentation files..."
        # Regenerate only the per-object dump subdirs. doc/db/ root holds no
        # generated docs — the security report moved to doc/db-security-report.md
        # (generated by test 008).
        find doc/db/table doc/db/view doc/db/function -type f -delete

        tables=$(doc_psql -t <<'EOS'
          SELECT schemaname || '.' || tablename
          FROM pg_catalog.pg_tables
          WHERE schemaname IN ('admin', 'db', 'lifecycle_callbacks', 'public', 'auth', 'worker', 'import')
          UNION ALL
          SELECT schemaname || '.' || matviewname
          FROM pg_catalog.pg_matviews
          WHERE schemaname IN ('admin', 'db', 'lifecycle_callbacks', 'public', 'auth', 'worker', 'import')
          ORDER BY 1;
EOS
)

        views=$(doc_psql -t <<'EOS'
          SELECT schemaname || '.' || viewname
          FROM pg_catalog.pg_views
          WHERE schemaname IN ('admin', 'db', 'lifecycle_callbacks', 'public', 'auth', 'worker', 'import')
            AND viewname NOT LIKE 'hypopg_%'
            AND viewname NOT LIKE 'pg_stat_%'
          ORDER BY 1;
EOS
)

        echo "$tables" | while read -r table; do
          if [ ! -z "$table" ]; then
            echo "Documenting table $table..."
            base_file="doc/db/table/${table//\./_}.md"

            echo '```sql' > "$base_file"
            doc_psql -c "\d+ $table" >> "$base_file"
            echo '```' >> "$base_file"
          fi
        done

        echo "$views" | while read -r view; do
          if [ ! -z "$view" ]; then
            echo "Documenting view $view..."
            base_file="doc/db/view/${view//\./_}.md"

            echo '```sql' > "$base_file"
            doc_psql -c "\d+ $view" >> "$base_file"
            echo '```' >> "$base_file"
          fi
        done

        functions=$(doc_psql -t <<'EOS'
          SELECT regexp_replace(
            n.nspname || '.' || p.proname || '(' ||
            regexp_replace(
              regexp_replace(
                regexp_replace(
                  pg_get_function_arguments(p.oid),
                  'timestamp with time zone',
                  'timestamptz',
                  'g'
                ),
                ',?\s*OUT [^,]+|\s*DEFAULT [^,]+|IN (\w+\s+)|INOUT (\w+\s+)',
                '\1',
                'g'
              ),
              '\w+\s+([^,]+)',
              '\1',
              'g'
            ) || ')',
            '"', '', 'g')
          FROM pg_proc p
          JOIN pg_namespace n ON p.pronamespace = n.oid
          WHERE n.nspname IN ('admin', 'db', 'lifecycle_callbacks', 'public', 'auth', 'worker', 'import')
            AND p.prokind != 'a'
            AND NOT EXISTS (
                SELECT 1 FROM pg_depend d
                JOIN pg_extension e ON d.refobjid = e.oid
                WHERE d.objid = p.oid
                  AND d.deptype = 'e'
            )
          ORDER BY 1;
EOS
)

        echo "$functions" | while read -r func; do
          if [ ! -z "$func" ]; then
            echo "Documenting function $func..."
            base_file="doc/db/function/${func//\./_}.md"

            echo '```sql' > "$base_file"
            doc_psql -c "\sf $func" >> "$base_file"
            echo '```' >> "$base_file"
          fi
        done

        echo "Database documentation generated in doc/db/{table,view,function}/"
        if [ "${DOCDB_STAMP_WITHHELD:-0}" = "1" ]; then
            # RUN_NO_STAMP: migrations/ was dirty at guard time — withhold the stamp.
            echo "DB documentation regenerated, but the freshness stamp was WITHHELD — migrations/"
            echo "had uncommitted changes at guard time. Commit, then re-run './dev.sh generate-doc-db'"
            echo "on a clean tree to write the release stamp (preflight requires it)."
        else
            mkdir -p "$WORKSPACE/tmp"
            # H1 two-line stamp:
            #   line 1: HEAD SHA at generation time
            #   line 2: source DB (test template) migration_version at generation time
            # SOURCE_VERSION captured above by ./sb assert-db-at-head.
            {
                git -C "$WORKSPACE" rev-parse HEAD
                echo "$SOURCE_VERSION"
            } > "$WORKSPACE/tmp/db-docs-passed-sha"
            echo "DB documentation stamp recorded: $(head -1 "$WORKSPACE/tmp/db-docs-passed-sha") (source version: $SOURCE_VERSION)"
        fi
        ;;
    'compile-run-and-trace-dev-app-in-container' )
        echo "Stopping app container..."
        docker compose --progress=plain --profile all down app
        echo "Building app container with profile 'all'..."
        docker compose --progress=plain --profile all build app
        echo "Starting app container with profile 'all' in detached mode..."
        docker compose --progress=plain --profile all up -d app
        echo "Following logs for app container..."
        docker compose logs --follow app
      ;;
    'setup-signing' )
        # Find SSH public keys
        SSH_KEYS=()
        for key_path in "$HOME/.ssh/id_ed25519.pub" "$HOME/.ssh/id_rsa.pub"; do
            if [ -f "$key_path" ]; then
                SSH_KEYS+=("$key_path")
            fi
        done

        if [ ${#SSH_KEYS[@]} -eq 0 ]; then
            echo "Error: No SSH public key found."
            echo "Looked for: ~/.ssh/id_ed25519.pub, ~/.ssh/id_rsa.pub"
            echo "Generate one with: ssh-keygen -t ed25519"
            exit 1
        fi

        if [ ${#SSH_KEYS[@]} -gt 1 ]; then
            echo "Multiple SSH keys found:"
            for i in "${!SSH_KEYS[@]}"; do
                fingerprint=$(ssh-keygen -l -f "${SSH_KEYS[$i]}" 2>/dev/null || echo "unknown fingerprint")
                echo "  [$((i+1))] ${SSH_KEYS[$i]} ($fingerprint)"
            done
            echo ""
            read -p "Select key [1-${#SSH_KEYS[@]}]: " -r choice < "$TTY_INPUT"
            if ! [[ "$choice" =~ ^[0-9]+$ ]] || [ "$choice" -lt 1 ] || [ "$choice" -gt ${#SSH_KEYS[@]} ]; then
                echo "Error: Invalid selection."
                exit 1
            fi
            KEY_PATH="${SSH_KEYS[$((choice-1))]}"
        else
            KEY_PATH="${SSH_KEYS[0]}"
        fi

        echo "Using SSH key: $KEY_PATH"
        fingerprint=$(ssh-keygen -l -f "$KEY_PATH" 2>/dev/null || echo "unknown fingerprint")
        echo "Fingerprint: $fingerprint"
        echo ""

        # Configure git at REPO level (not global)
        git config gpg.format ssh
        git config user.signingKey "$KEY_PATH"
        git config commit.gpgsign true
        git config tag.gpgsign true

        echo "Signing configured. All commits and tags will be signed with $KEY_PATH"
        echo "Remember to enable 'Require signed commits' on master in GitHub branch protection"
      ;;
    'build-sb' )
        # Lego primitive: build ONE sb binary.
        #   No args     → host platform → write to ./sb (daily-driver path).
        #   <os>/<arch> → cross-compile → write sb-<os>-<arch>; ./sb unchanged.
        # cross-build-sb composes this primitive across all 4 platforms.
        if [ -z "${1:-}" ]; then
            TARGET="$(go env GOOS)/$(go env GOARCH)"
            OUTPUT="sb"
        else
            TARGET="$1"
            OS=${TARGET%/*}
            ARCH=${TARGET#*/}
            OUTPUT="sb-${OS}-${ARCH}"
        fi
        OS=${TARGET%/*}
        ARCH=${TARGET#*/}
        VERSION=$(git describe --tags --always --match 'v[0-9]*' 2>/dev/null || echo "dev")
        # Full 40-char SHA — see note at line ~51 for rationale.
        COMMIT=$(git rev-parse HEAD 2>/dev/null || echo "unknown")
        LDFLAGS="-s -w -X 'github.com/statisticsnorway/statbus/cli/cmd.version=${VERSION}' -X 'github.com/statisticsnorway/statbus/cli/cmd.commit=${COMMIT}'"
        (cd cli && CGO_ENABLED=0 GOOS=$OS GOARCH=$ARCH go build -trimpath -ldflags "$LDFLAGS" -o "../$OUTPUT" .)
        echo "Built sb ${VERSION} for ${OS}/${ARCH} → ${OUTPUT}"
      ;;
    'cross-build-sb' )
        # Composed command — build all four target platforms and refresh
        # ./sb to the host variant so the daily-driver remains usable
        # after a release-packaging build. Pointed at by the identity-
        # guard error message as the safe default; the operator never
        # needs to know which platform they're on a priori.
        for t in darwin/arm64 darwin/amd64 linux/arm64 linux/amd64; do
            ./dev.sh build-sb "$t"
        done
        HOST_OS=$(go env GOOS)
        HOST_ARCH=$(go env GOARCH)
        if [ -f "sb-${HOST_OS}-${HOST_ARCH}" ]; then
            cp "sb-${HOST_OS}-${HOST_ARCH}" sb
            echo "Refreshed: ./sb → sb-${HOST_OS}-${HOST_ARCH}"
        fi
      ;;
    'test-install' )
        # End-to-end install test using a Hetzner Cloud cx23 VM (~€0.0072/run,
        # one billing hour minimum). Replaces the prior Multipass-on-macOS
        # workflow, which kept breaking on macOS vmnet state after network
        # swaps (VPN, hotspot, mobile-network) — recovery required `sudo
        # reboot`, destroying every concurrent dev session.
        #
        # Delegates to the 0-happy-install scenario of the install-recovery harness: same
        # workflow (bootstrap clean VM → run `./sb install` → assert health,
        # step 9, step 15, systemd active) but Hetzner-backed and reachable
        # from any internet connection.
        #
        # The test-install.yaml workflow on GitHub Actions is the gate consumed
        # by ./sb release stable; local invocation is for operator sanity-check only.
        #
        # Requires HCLOUD_TOKEN in .env.credentials (auto-sourced by
        # test/install-recovery/lib/vm-bootstrap.sh).
        set -euo pipefail

        INSTALL_VERSION="${1:-}"  # optional: use published release instead of local build

        echo "=== StatBus Install Test (Hetzner Cloud) ==="
        echo ""

        # Run the 0-happy-install scenario with explicit exit-code capture rather than
        # relying solely on set -e. Belt-and-suspenders: the false-positive
        # release-gate class (test silently passes despite a real failure)
        # is severe enough to warrant the explicit check, in addition to
        # the implicit set -e abort path.
        set +e
        INSTALL_VERSION="$INSTALL_VERSION" \
            "$WORKSPACE/test/install-recovery/scenarios/0-happy-install.sh"
        scenario_exit=$?
        set -e

        if [ "$scenario_exit" -ne 0 ]; then
            echo "" >&2
            echo "ERROR: 0-happy-install scenario exited $scenario_exit." >&2
            exit "$scenario_exit"
        fi

        echo ""
        echo "Install test complete."
      ;;
    'test-install-recovery' )
        # End-to-end install RECOVERY tests (Hetzner Cloud). Sister to
        # test-install: validates wedge-recovery scenarios that the install
        # ladder must survive (Stage A killed migrate, B pool exhaustion,
        # C systemd failed, D advisory zombie, E worker busy, F SIGKILL
        # mid-upgrade, plus happy paths and bool-text regression).
        #
        # Each scenario is a fresh Hetzner cx23 VM. ~15-25 min per scenario.
        # See test/install-recovery/README.md for the catalogue.
        exec bash "$WORKSPACE/test/install-recovery/run.sh" "$@"
      ;;
    'test-assert-db-at-head' )
        # Smoke test for the `./sb assert-db-at-head` Cobra subcommand
        # (Go implementation in cli/internal/migrate/at_head.go;
        # CLI surface in cli/cmd/assert_db_at_head.go). Verifies two
        # invariants:
        #   1. Subcommand passes when called against the seed (canonical
        #      source-of-truth, queryable, has full db.migration set).
        #   2. Subcommand REFUSES cleanly when called against a PG
        #      template (datistemplate=true, ALLOW_CONNECTIONS=false).
        #      Templates aren't directly queryable; without the defense
        #      the subcommand silently returns empty and computes a
        #      bogus "BEHIND HEAD by N migrations" diagnostic.
        #
        # Default target for case 1: statbus_seed.
        # Optional override: ./dev.sh test-assert-db-at-head <db_name>.
        #
        # Pre-conditions:
        #   - statbus_seed must exist (./dev.sh recreate-seed).
        #   - statbus_test_template SHOULD exist for case 2 (skipped if not).
        #
        # Exits 0 on PASS, 1 on FAIL.
        eval $(./dev.sh postgres-variables)
        SEED_NAME="${1:-${POSTGRES_SEED_DB:-statbus_seed}}"
        TEMPLATE_NAME="${POSTGRES_TEST_DB:-statbus_test_template}"

        if ! ./sb psql -d postgres -t -A -c \
                "SELECT 1 FROM pg_database WHERE datname = '$SEED_NAME';" \
                2>/dev/null | grep -q '^1$'; then
            echo "SKIP: seed DB '$SEED_NAME' does not exist."
            echo "  Bootstrap: ./dev.sh recreate-seed"
            exit 0
        fi

        # Case 1: assert against the seed (canonical source-of-truth).
        echo "=== Case 1: seed (datistemplate=false, expected to PASS) ==="
        echo "Target: $SEED_NAME"
        set +e
        seed_output=$(./sb assert-db-at-head "$SEED_NAME" "./dev.sh test-assert-db-at-head:seed")
        seed_rc=$?
        set -e
        if [ $seed_rc -eq 0 ]; then
            echo "PASS: returned 0 (seed at HEAD)"
            echo "      Reported max migration version: $seed_output"
            if ! [[ "$seed_output" =~ ^[0-9]{14}$ ]]; then
                echo "WARN: returned version '$seed_output' is not a 14-digit timestamp." >&2
            fi
        else
            echo "FAIL: returned $seed_rc against seed (expected 0)."
            echo "      Captured output: '$seed_output'"
            echo "      (subcommand's stderr above explains the refusal reason)"
            exit 1
        fi
        echo ""

        # Case 2: defensive refusal when pointed at a template.
        if ! ./sb psql -d postgres -t -A -c \
                "SELECT 1 FROM pg_database WHERE datname = '$TEMPLATE_NAME';" \
                2>/dev/null | grep -q '^1$'; then
            echo "=== Case 2: template (skipped — '$TEMPLATE_NAME' not present) ==="
            echo "SKIP: bootstrap via ./dev.sh create-test-template to enable this case"
            exit 0
        fi
        is_template=$(./sb psql -d postgres -t -A -c \
            "SELECT datistemplate FROM pg_database WHERE datname = '$TEMPLATE_NAME';" \
            2>/dev/null | tr -d '[:space:]')
        echo "=== Case 2: template (datistemplate=$is_template, expected to REFUSE cleanly) ==="
        echo "Target: $TEMPLATE_NAME"
        set +e
        tmpl_output=$(./sb assert-db-at-head "$TEMPLATE_NAME" "./dev.sh test-assert-db-at-head:template" 2>&1 >/dev/null)
        tmpl_rc=$?
        set -e
        if [ $tmpl_rc -eq 0 ]; then
            echo "FAIL: subcommand returned 0 for template '$TEMPLATE_NAME' — expected REFUSE."
            echo "      The defensive template-refusal in migrate.AssertDBAtHead is not firing."
            exit 1
        fi
        # Confirm the refusal reason names the template-not-queryable cause.
        if echo "$tmpl_output" | grep -q "is a PG template"; then
            echo "PASS: refused cleanly (exit $tmpl_rc), naming the template-not-queryable cause."
            echo "      Sample of subcommand's stderr:"
            echo "$tmpl_output" | sed 's/^/        /'
        else
            echo "FAIL: subcommand refused (exit $tmpl_rc) but error didn't mention 'is a PG template'."
            echo "      Captured stderr:"
            echo "$tmpl_output" | sed 's/^/        /'
            exit 1
        fi
        echo ""
        echo "All cases passed."
      ;;
    'test-stamp-guard' )
        # Self-contained unit test for check_stamp_guard's version-coherence
        # check (db-docs-skip-catch22 fix). Verifies three scenarios without a
        # live DB: the catch-22 bug is fixed, normal-SKIP still works, and the
        # genuine-needs-regen path still works.
        #
        # Fixture: a temp stamp file in tmp/ (auto-deleted). No DB, no regen.
        #
        # Exit 0 on ALL-PASS, 1 on any failure.
        _tsg_pass=0; _tsg_fail=0
        _tsg_stamp_basename="test-stamp-guard-$$"
        _tsg_stamp_path="$WORKSPACE/tmp/$_tsg_stamp_basename"
        # Extensionless ON PURPOSE: NOT *.tmp (gitignored — .gitignore:129) and NOT
        # *.up.sql/.down.sql (would look like a real migration). git status must
        # report it as untracked for Test 5 to force a dirty migrations/. (A *.tmp
        # name silently neutered this test once — Test 5 now self-checks for it.)
        _tsg_dirty_marker="$WORKSPACE/migrations/TSG_DIRTY_MARKER_$$"
        # shellcheck disable=SC2064
        trap "rm -f '$_tsg_stamp_path' '$_tsg_dirty_marker'" EXIT

        _tsg_head_sha=$(git -C "$WORKSPACE" rev-parse HEAD 2>/dev/null)
        _tsg_disk_max=$(find "$WORKSPACE/migrations" -maxdepth 1 \
            \( -name '*.up.sql' -o -name '*.up.psql' \) 2>/dev/null \
            | sed -E 's|.*/([0-9]{14})_.*|\1|' | sort -r | head -1)

        if [ -z "$_tsg_disk_max" ]; then
            echo "SKIP: no on-disk migrations found — test requires at least one migration file."
            exit 0
        fi

        _tsg_assert_rc() {
            local _label="$1" _expected="$2" _actual="$3"
            if [ "$_actual" -eq "$_expected" ]; then
                echo "[PASS] $_label"
                _tsg_pass=$((_tsg_pass+1))
            else
                echo "[FAIL] $_label — expected rc=$_expected, got rc=$_actual"
                _tsg_fail=$((_tsg_fail+1))
            fi
        }

        # Tests 1-4 exercise the stamp-logic branches, reached ONLY on a clean
        # migrations/ (the dirty branch returns RUN_NO_STAMP first, rc 3). Skip
        # them when the tree is dirty; Test 5 covers the dirty path.
        _tsg_migrations_dirty=$(git -C "$WORKSPACE" status --porcelain -- migrations 2>/dev/null)
        if [ -n "$_tsg_migrations_dirty" ]; then
            echo "[SKIP] stamp-logic tests 1-4: migrations/ is dirty (guard returns RUN_NO_STAMP"
            echo "       rc=3 before the stamp-logic branches). Test 5 covers the dirty path."
        else
        # ── Test 1: catch-22 — SHA=HEAD, version stale (higher than disk max) ──
        # Before fix: SKIP (rc=1). After fix: RUNNING (rc=0).
        printf '%s\n%s\n' "$_tsg_head_sha" "20991231235959" > "$_tsg_stamp_path"
        set +e
        check_stamp_guard "test:catch-22-stale-high" "$_tsg_stamp_basename" "migrations" >/dev/null 2>&1
        _tsg_rc=$?
        set -e
        _tsg_assert_rc "catch-22: SHA=HEAD, version stale (20991231235959 > disk max) → RUNNING" 0 "$_tsg_rc"

        # ── Test 2: catch-22 variant — SHA=HEAD, version stale (lower than disk max) ──
        # Applied migration later deleted from tree; stamp records old version.
        printf '%s\n%s\n' "$_tsg_head_sha" "19991231235959" > "$_tsg_stamp_path"
        set +e
        check_stamp_guard "test:catch-22-stale-low" "$_tsg_stamp_basename" "migrations" >/dev/null 2>&1
        _tsg_rc=$?
        set -e
        _tsg_assert_rc "catch-22: SHA=HEAD, version stale (19991231235959 < disk max) → RUNNING" 0 "$_tsg_rc"

        # ── Test 3: normal SKIP — SHA=HEAD, version matches disk max ──
        # Both axes agree: no regen needed. migrations/ is clean here (the outer
        # guard skipped tests 1-4 otherwise).
        printf '%s\n%s\n' "$_tsg_head_sha" "$_tsg_disk_max" > "$_tsg_stamp_path"
        set +e
        check_stamp_guard "test:normal-skip" "$_tsg_stamp_basename" "migrations" >/dev/null 2>&1
        _tsg_rc=$?
        set -e
        _tsg_assert_rc "normal SKIP: SHA=HEAD, version matches disk max → SKIP (rc=1)" 1 "$_tsg_rc"

        # ── Test 4: genuine needs-regen — SHA is ancestor, migrations changed ──
        # Pre-existing RUNNING behavior: stamp SHA is before the most recent
        # migration-file commit. Find that ancestor.
        # git log --format='%H' emits GPG signature lines interspersed with SHAs
        # when log.showSignature is set; filter to 40-hex lines only.
        _tsg_migration_commit=$(git -C "$WORKSPACE" log --format='%H' \
            -- 'migrations/*.up.sql' 'migrations/*.up.psql' 2>/dev/null \
            | grep -E '^[0-9a-f]{40}$' | head -1 || true)
        _tsg_ancestor_sha=$(git -C "$WORKSPACE" rev-parse "${_tsg_migration_commit}^" 2>/dev/null || echo "")
        _tsg_ancestor_changed=""
        if [ -n "$_tsg_ancestor_sha" ] && \
           git -C "$WORKSPACE" merge-base --is-ancestor "$_tsg_ancestor_sha" HEAD 2>/dev/null; then
            _tsg_ancestor_changed=$(git -C "$WORKSPACE" diff --name-only \
                "$_tsg_ancestor_sha" HEAD -- migrations 2>/dev/null)
        fi
        if [ -n "$_tsg_ancestor_changed" ]; then
            printf '%s\n%s\n' "$_tsg_ancestor_sha" "$_tsg_disk_max" > "$_tsg_stamp_path"
            set +e
            check_stamp_guard "test:genuine-regen" "$_tsg_stamp_basename" "migrations" >/dev/null 2>&1
            _tsg_rc=$?
            set -e
            _tsg_assert_rc "genuine regen: SHA=ancestor with migration changes → RUNNING (rc=0)" 0 "$_tsg_rc"
        else
            echo "[SKIP] genuine-regen test: could not find ancestor with migration changes"
        fi
        fi  # end stamp-logic tests 1-4 (clean-tree only)

        # ── Test 5: dirty migrations/ → RUN_NO_STAMP (rc=3), guard writes NO stamp ──
        # Force a dirty migrations/ with a throwaway untracked marker (an extensionless
        # file git reports as untracked — NOT a *.up.sql migration, NOT *.tmp/gitignored).
        # Assert the guard RUNS-
        # without-stamp (rc=3, the FIRST branch, ahead of the stamp logic) AND that
        # it left the stamp file byte-for-byte unchanged: the guard must NEVER write
        # a stamp; the CALLER gates the write on rc=3. Regression guard for the
        # "3 write sites gate together" invariant.
        echo "throwaway dirty marker for test-stamp-guard self-test" > "$_tsg_dirty_marker"
        # Self-check: the marker MUST actually dirty migrations/. If a .gitignore
        # rule hides it (exactly the *.tmp bug caught 2026-06), the test would
        # silently stop exercising the dirty path — fail LOUD instead of false-pass.
        if ! git -C "$WORKSPACE" status --porcelain -- migrations 2>/dev/null | grep -q 'TSG_DIRTY_MARKER'; then
            echo "[FAIL] Test 5 setup: dirty marker is gitignored/invisible to git — cannot"
            echo "       exercise the dirty path. Pick a marker git reports (not *.tmp; see .gitignore)."
            _tsg_fail=$((_tsg_fail+1))
            rm -f "$_tsg_dirty_marker"
        else
            # Stamp present + coherent so that, absent the dirty branch, the guard would
            # SKIP (rc=1); getting rc=3 proves the dirty branch fired first.
            printf '%s\n%s\n' "$_tsg_head_sha" "$_tsg_disk_max" > "$_tsg_stamp_path"
            _tsg_stamp_before=$(cat "$_tsg_stamp_path" 2>/dev/null)
            set +e
            check_stamp_guard "test:dirty-run-no-stamp" "$_tsg_stamp_basename" "migrations" >/dev/null 2>&1
            _tsg_rc=$?
            set -e
            rm -f "$_tsg_dirty_marker"
            _tsg_assert_rc "dirty migrations/ → RUN_NO_STAMP (rc=3, not REFUSE)" 3 "$_tsg_rc"
            _tsg_stamp_after=$(cat "$_tsg_stamp_path" 2>/dev/null || echo "<gone>")
            if [ "$_tsg_stamp_before" = "$_tsg_stamp_after" ]; then
                echo "[PASS] dirty path: guard wrote NO stamp (stamp file unchanged)"
                _tsg_pass=$((_tsg_pass+1))
            else
                echo "[FAIL] dirty path: guard altered the stamp file — it must never write a stamp"
                _tsg_fail=$((_tsg_fail+1))
            fi
        fi

        # ── Test 6 (STATBUS-079): write-site source-assert ──────────────────
        # Each of the 3 stamp-write sites must be GATED by its withhold decision.
        # Test 5 only proves the GUARD returns rc 3 + writes nothing; it does NOT
        # prove the CALLERS withhold the stamp. This catches a future UNGATING of
        # a write site (which would write a dirty-provenance stamp — the exact bug
        # the gate fix prevents). Source-structure check: the gate token must
        # appear within the window of lines immediately above each stamp-write line.
        _s079_assert_gated() {
            local _label="$1" _file="$2" _write="$3" _gate="$4" _window="${5:-14}"
            local _ln _start _ctx
            _ln=$(grep -nF -- "$_write" "$_file" 2>/dev/null | head -1 | cut -d: -f1)
            if [ -z "$_ln" ]; then
                echo "[FAIL] $_label: write site not found ($_write) — source moved? update Test 6"
                _tsg_fail=$((_tsg_fail+1)); return
            fi
            _start=$(( _ln > _window ? _ln - _window : 1 ))
            _ctx=$(sed -n "${_start},${_ln}p" "$_file")
            if printf '%s' "$_ctx" | grep -qF -- "$_gate"; then
                echo "[PASS] $_label: stamp write gated by $_gate"
                _tsg_pass=$((_tsg_pass+1))
            else
                echo "[FAIL] $_label: stamp write ($_write) NOT within a '$_gate' gate — ungated dirty-stamp risk (STATBUS-079)"
                _tsg_fail=$((_tsg_fail+1))
            fi
        }
        _s079_assert_gated "fast-test write" "$WORKSPACE/dev.sh"           '> "$WORKSPACE/tmp/fast-test-passed-sha"' 'FAST_STAMP_WITHHELD'
        _s079_assert_gated "db-docs write"   "$WORKSPACE/dev.sh"           '> "$WORKSPACE/tmp/db-docs-passed-sha"'   'DOCDB_STAMP_WITHHELD'
        _s079_assert_gated "types write"     "$WORKSPACE/cli/cmd/types.go" 'os.WriteFile(stampPath'                  'stampGuardRunNoStamp'

        echo ""
        echo "Results: $_tsg_pass passed, $_tsg_fail failed"
        [ $_tsg_fail -eq 0 ] && exit 0 || exit 1
      ;;
    'upgrade-sandbox' )
      # Isolated upgrade-service test harness on port offset 9 (3090-3094).
      # Collision-free with dev/ma/no slots (offsets 1/2/3 = 3010/3020/3030).
      # All credentials are hardcoded in docker/compose/upgrade-sandbox.yml.
      SANDBOX_COMPOSE="${WORKSPACE}/docker/compose/upgrade-sandbox.yml"
      SANDBOX_CMD="${1:-}"
      shift || true
      case "$SANDBOX_CMD" in
        'up' )
          echo "Starting upgrade sandbox (db=3094, rest=3093, app=3092)..."
          docker compose -f "$SANDBOX_COMPOSE" up -d --wait
          echo "Sandbox up. psql: ./dev.sh upgrade-sandbox psql"
          ;;
        'down' )
          docker compose -f "$SANDBOX_COMPOSE" down -v
          ;;
        'status' )
          docker compose -f "$SANDBOX_COMPOSE" ps
          ;;
        'psql' )
          docker compose -f "$SANDBOX_COMPOSE" exec db \
            psql -U postgres statbus_sandbox "$@"
          ;;
        * )
          echo "Usage: ./dev.sh upgrade-sandbox <up|down|status|psql>"
          echo ""
          echo "  up      Start sandbox services (detached, waits for healthy)"
          echo "  down    Stop and remove sandbox containers + volumes"
          echo "  status  Show container status"
          echo "  psql    Open psql in the sandbox database"
          if [ -n "$SANDBOX_CMD" ]; then
              echo ""
              echo "Error: Unknown subcommand '$SANDBOX_CMD'"
              exit 1
          fi
          ;;
      esac
      ;;
     * )
      echo "dev.sh — Development-only commands for StatBus"
      echo ""
      echo "Usage: ./dev.sh <command> [args...]"
      echo ""
      echo "Database lifecycle (DESTRUCTIVE - local dev only):"
      echo "  create-db                          Create database with migrations"
      echo "  delete-db                          Delete database and data directory"
      echo "  recreate-database                  Delete + create (fresh start)"
      echo "  create-db-structure                Run migrations (seed + incremental)"
      echo "  delete-db-structure                Roll back all migrations"
      echo "  reset-db-structure                 Roll back + re-apply all migrations"
      echo ""
      echo "Testing:"
      echo "  test <all|fast|benchmarks|name>    Run pg_regress tests (check-don't-fix preconditions)"
      echo "  migrate-and-test <args...>         CI-friendly: bootstrap seed + test template, then test"
      echo "  test-isolated <name>               Run single test in isolated database"
      echo "  continous-integration-test [branch] [commit]  Full CI test pipeline"
      echo "  diff-fail-first [gui|vim|pipe]     Show diff for first failed test"
      echo "  diff-fail-all [gui|vim|pipe]       Show diffs for all failed tests"
      echo "  make-all-failed-test-results-expected  Accept all test failures"
      echo "  create-test-template               Clone POSTGRES_SEED_DB → POSTGRES_TEST_DB"
      echo "  clean-test-databases [--force]     Drop all test_* databases"
      echo ""
      echo "Seed lifecycle (build-time canonical schema):"
      echo "  create-seed                        Create empty \${POSTGRES_SEED_DB} from template_statbus"
      echo "  delete-seed                        Drop \${POSTGRES_SEED_DB}"
      echo "  recreate-seed                      Rebuild \${POSTGRES_SEED_DB} from the statbus-seed image + incremental"
      echo "                                       migrations (~5-15s typical). FULL_REPLAY=1 forces from-zero replay"
      echo "                                       (~1-3min). STATBUS_DB_SEED_NO_FETCH=1 uses cached artifact only."
      echo "  seed-status                        Compare seed DB to migrations/ at HEAD (set diff)"
      echo "  seed-clone <target>                Clone seed → <target> via pg CREATE DATABASE WITH TEMPLATE"
      echo ""
      echo "Seed publishing & documentation:"
      echo "  dump-seed                          Save database seed for fast restore"
      echo "  list-seeds                         List available seeds"
      echo "  generate-doc-db                    Generate schema docs in doc/db/"
      echo "  generate-types                     Generate TypeScript types from schema"
      echo ""
      echo "Upgrade sandbox (port offset 9 — 3090-3094, isolated from dev slots):"
      echo "  upgrade-sandbox up                 Start sandbox: db/rest/worker/app"
      echo "  upgrade-sandbox down               Stop and remove sandbox containers + volumes"
      echo "  upgrade-sandbox status             Show sandbox container status"
      echo "  upgrade-sandbox psql               Open psql in statbus_sandbox database"
      echo ""
      echo "Build:"
      echo "  test-install                       End-to-end install test via Multipass VM"
      echo "  test-assert-db-at-head [db]        Smoke-test the ./sb assert-db-at-head Cobra subcommand"
      echo "  build-sb [target]                  Build sb. No args: host → ./sb. <os>/<arch>: cross → sb-<os>-<arch>."
      echo "  cross-build-sb                     Build all 4 platforms + refresh ./sb to host variant."
      echo ""
      echo "Git:"
      echo "  setup-signing                      Configure SSH commit signing for this repo"
      echo ""
      echo "Helpers:"
      echo "  postgres-variables                 Export PG connection variables"
      echo "  is-db-running                      Check if database is accepting connections"
      echo ""
      echo "For production/ops commands, use ./sb (start, stop, psql, migrate, etc.)"
      if [ -n "$action" ]; then
          echo ""
          echo "Error: Unknown command '$action'"
          exit 1
      fi
      ;;
esac
