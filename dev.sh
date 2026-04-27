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

# Rebuild ./sb when:
#   - the binary doesn't exist, OR
#   - any cli/**/*.go source is newer than the binary (developer pulled
#     new code, or hot-edited locally — without this check, dev.sh would
#     keep using the stale binary and developers would chase ghost bugs).
sb_needs_rebuild=false
if ! test -x ./sb; then
    sb_needs_rebuild=true
elif [ -n "$(find cli -name '*.go' -newer ./sb -print -quit 2>/dev/null)" ]; then
    sb_needs_rebuild=true
fi
if [ "$sb_needs_rebuild" = true ]; then
    if command -v go >/dev/null 2>&1; then
        echo "Building sb from source..."
        # Inject version from git describe. Strip "v" prefix to match release.yaml
        # convention — service.go adds "v" back, avoiding double-v.
        # --match 'v[0-9]*' restricts git describe to release tags. The moving
        # install-verified tag was deleted in rc.62; this filter remains as
        # defense against any stray non-release tags landing in the refs/tags/ space.
        _SB_VERSION=$(git describe --tags --always --match 'v[0-9]*' 2>/dev/null | sed 's/^v//' || echo "dev")
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
if [ ! -f "$WORKSPACE/.db-seed/seed.pg_dump" ] && [ -x ./sb ]; then
    ./sb db seed fetch
fi

# Set TTY_INPUT to /dev/tty if available (interactive), otherwise /dev/null
if [ -e /dev/tty ]; then
  export TTY_INPUT=/dev/tty
else
  export TTY_INPUT=/dev/null
fi

# ---- Tier-1 stamp guard ----
#
# Used by `./dev.sh test fast`, `./dev.sh generate-db-documentation`, and
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

    # REFUSE: any file inside the scope (minus excludes) has uncommitted
    # staged or unstaged changes. A stamp written on top of that would lie.
    local dirty
    dirty=$(git -C "$WORKSPACE" status --porcelain -- "${scopes[@]}" "${excludes[@]}" 2>/dev/null)
    if [ -n "$dirty" ]; then
        echo "REFUSED: $label"
        echo "Reason:  ${scopes[*]} has uncommitted changes — stamping would not"
        echo "         honestly reflect HEAD."
        echo "Evidence:"
        printf '%s\n' "$dirty" | sed 's/^/  /'
        echo "Override: commit or stash the changes, or set FORCE=1 to bypass."
        return 2
    fi

    if [ ! -f "$stamp_path" ]; then
        echo "RUNNING: $label"
        echo "Reason:  no stamp at tmp/$stamp_basename — no prior successful run to skip."
        return 0
    fi

    local stamp_sha
    stamp_sha=$(tr -d '[:space:]' < "$stamp_path" 2>/dev/null)
    if [ -z "$stamp_sha" ]; then
        echo "RUNNING: $label"
        echo "Reason:  stamp tmp/$stamp_basename is empty."
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

action=${1:-}
shift || true

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
            _SB_VERSION=$(git describe --tags --always --match 'v[0-9]*' 2>/dev/null | sed 's/^v//' || echo "dev")
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
        if [ "${TEST_ARGS[0]}" = "fast" ]; then
            set +e
            check_stamp_guard "./dev.sh test fast" "fast-test-passed-sha" "migrations" "test"
            guard_rc=$?
            set -e
            case $guard_rc in
                0) : ;;
                1) exit 0 ;;
                2) exit 1 ;;
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

        # Precondition checks (plan section R commit 4: check, don't fix).
        # `./dev.sh test ...` is human-facing — refuses to run with stale
        # state and prints the exact remediation command. CI/automation
        # that wants auto-rebuild should call `./dev.sh migrate-and-test ...`
        # instead.
        SEED_NAME="${POSTGRES_SEED_DB:-statbus_seed}"
        TEMPLATE_NAME_PRECHECK="${POSTGRES_TEST_DB:-statbus_test_template}"
        LATEST_MIGRATION=$(for f in "$WORKSPACE/migrations/"*.up.sql "$WORKSPACE/migrations/"*.up.psql; do
            [ -e "$f" ] || continue
            basename "$f" | cut -d_ -f1
        done | sort | tail -1)

        # Check 1: seed exists.
        SEED_EXISTS_PRECHECK=$(./sb psql -d postgres -t -A -c \
            "SELECT 1 FROM pg_database WHERE datname = '$SEED_NAME';" 2>/dev/null || echo "0")
        if [ "$SEED_EXISTS_PRECHECK" != "1" ]; then
            echo "Test precondition failed: seed database '$SEED_NAME' does not exist."
            echo "  Run:  ./dev.sh recreate-seed"
            echo "  Or:   ./dev.sh migrate-and-test ${TEST_ARGS[*]}  (composition that auto-rebuilds)"
            exit 1
        fi

        # Check 2: seed at HEAD.
        SEED_MAX_VERSION=$(./sb psql -d "$SEED_NAME" -t -A -c \
            "SELECT MAX(version) FROM db.migration" 2>/dev/null | tr -d ' ' || true)
        if [ -n "$LATEST_MIGRATION" ] && [ "$SEED_MAX_VERSION" != "$LATEST_MIGRATION" ]; then
            echo "Test precondition failed: seed at version '$SEED_MAX_VERSION', HEAD has '$LATEST_MIGRATION'."
            echo "  Run:  ./sb migrate up --target seed"
            echo "  Or:   ./dev.sh migrate-and-test ${TEST_ARGS[*]}  (composition that auto-rebuilds)"
            exit 1
        fi

        # Check 3: test template cloned from current seed (stamp matches latest).
        TEMPLATE_STAMP=""
        if [ -f "$WORKSPACE/tmp/test-template-migrations-sha" ]; then
            TEMPLATE_STAMP=$(cat "$WORKSPACE/tmp/test-template-migrations-sha")
        fi
        if [ -n "$LATEST_MIGRATION" ] && [ "$TEMPLATE_STAMP" != "$LATEST_MIGRATION" ]; then
            echo "Test precondition failed: test template stamp '$TEMPLATE_STAMP' != latest migration '$LATEST_MIGRATION'."
            echo "  Run:  ./dev.sh create-test-template"
            echo "  Or:   ./dev.sh migrate-and-test ${TEST_ARGS[*]}  (composition that auto-rebuilds)"
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
                    cp "$result_file" "$expected_file"
                else
                    echo "Warning: Result file not found for test: '$test_basename'. Cannot update expected output."
                fi
            done
        fi

        # Write the stamp unconditionally on success — the upfront REFUSE
        # guard already verified migrations/ and test/ (minus non-strict
        # baselines) were clean at RUN time, so HEAD is an honest anchor.
        # No silent skip: if we got here, we stamp.
        if [ $OVERALL_EXIT_CODE -eq 0 ]; then
            mkdir -p "$WORKSPACE/tmp"
            git rev-parse HEAD > "$WORKSPACE/tmp/fast-test-passed-sha"
            echo "Fast test stamp recorded: $(cat "$WORKSPACE/tmp/fast-test-passed-sha")"
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
        TEMPLATE_STAMP=""
        if [ -f "$WORKSPACE/tmp/test-template-migrations-sha" ]; then
            TEMPLATE_STAMP=$(cat "$WORKSPACE/tmp/test-template-migrations-sha")
        fi
        if [ "$TEMPLATE_STAMP" != "$LATEST_MIGRATION" ]; then
            echo "migrate-and-test: test template stale (stamp='$TEMPLATE_STAMP', want '$LATEST_MIGRATION'). Rebuilding..."
            ./dev.sh create-test-template
        else
            echo "migrate-and-test: test template already at $TEMPLATE_STAMP."
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
                cp -f "$WORKSPACE/test/results/$test.out" "$WORKSPACE/test/expected/$test.out"
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

        # Drop any existing template — clone won't replace.
        TEMPLATE_EXISTS=$(./sb psql -d postgres -t -A -c \
            "SELECT 1 FROM pg_database WHERE datname = '$TEMPLATE_NAME';" 2>/dev/null || echo "0")
        if [ "$TEMPLATE_EXISTS" = "1" ]; then
            echo "Existing template found, removing it..."

            ./sb psql -d postgres -c "
                SELECT pg_terminate_backend(pid)
                FROM pg_stat_activity
                WHERE datname = '$TEMPLATE_NAME';
            " || true

            if ! ./sb psql -d postgres -c "
                UPDATE pg_database SET datistemplate = false WHERE datname = '$TEMPLATE_NAME';
            "; then
                echo "Error: Failed to unmark template database. Check permissions."
                exit 1
            fi

            if ! ./sb psql -d postgres -c "DROP DATABASE $TEMPLATE_NAME;"; then
                echo "Error: Failed to drop existing template database."
                echo "There may be active connections. Check with:"
                echo "  ./sb psql -c \"SELECT * FROM pg_stat_activity WHERE datname = '$TEMPLATE_NAME';\""
                exit 1
            fi
        fi

        # Fast clone via the seed-clone primitive.
        ./dev.sh seed-clone "$TEMPLATE_NAME"

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

        # Record the latest migration timestamp so `./dev.sh test fast`
        # precondition check can detect when the template is stale.
        # Includes both .up.sql and .up.psql migrations.
        LATEST_MIGRATION=$(for f in "$WORKSPACE/migrations/"*.up.sql "$WORKSPACE/migrations/"*.up.psql; do
            [ -e "$f" ] || continue
            basename "$f" | cut -d_ -f1
        done | sort | tail -1)
        if [ -n "$LATEST_MIGRATION" ]; then
            mkdir -p "$WORKSPACE/tmp"
            echo "$LATEST_MIGRATION" > "$WORKSPACE/tmp/test-template-migrations-sha"
            echo "Test template migration stamp recorded: $LATEST_MIGRATION"
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
    # `./sb db seed create` artifact published to origin/db-seed.
    'create-seed' )
        eval $(./dev.sh postgres-variables)
        SEED_NAME="${POSTGRES_SEED_DB:-statbus_seed}"

        echo "Creating empty seed database from template_statbus: $SEED_NAME"

        SEED_EXISTS=$(./sb psql -d postgres -t -A -c \
            "SELECT 1 FROM pg_database WHERE datname = '$SEED_NAME';" 2>/dev/null || echo "0")
        if [ "$SEED_EXISTS" = "1" ]; then
            echo "Error: seed database '$SEED_NAME' already exists."
            echo "  Drop it first: ./dev.sh delete-seed"
            echo "  Or rebuild end-to-end: ./dev.sh recreate-seed"
            exit 1
        fi

        # Pre-flight: confirm template_statbus exists (provisioned by
        # ./dev.sh create-db). Without this check the CREATE below
        # fails with a generic "template not found" that doesn't name
        # the recovery command.
        if ! TEMPLATE_STATBUS_EXISTS=$(./sb psql -d postgres -t -A -c \
                "SELECT 1 FROM pg_database WHERE datname = 'template_statbus';" 2>&1); then
            echo "Error: cannot reach Postgres to check for template_statbus."
            echo "  Underlying psql error: $TEMPLATE_STATBUS_EXISTS"
            exit 1
        fi
        if [ "$TEMPLATE_STATBUS_EXISTS" != "1" ]; then
            echo "Error: template_statbus does not exist."
            echo "  Provisioned by: ./dev.sh create-db"
            exit 1
        fi

        if ! ./sb psql -d postgres -c "
            CREATE DATABASE $SEED_NAME
            WITH TEMPLATE template_statbus
            OWNER postgres;
        "; then
            echo "Error: Failed to create seed database from template_statbus."
            exit 1
        fi

        # Set up roles and schemas that init-db.sh creates for the main
        # DB but are not in template_statbus. Roles are cluster-wide
        # (already exist), but the auth schema and grants must be
        # per-database. Mirrors create-test-template.
        echo "Setting up schemas and grants for seed..."
        ./sb psql -d $SEED_NAME -v ON_ERROR_STOP=1 <<'EOF'
            CREATE SCHEMA IF NOT EXISTS auth;
            GRANT USAGE ON SCHEMA auth TO authenticated;
            GRANT USAGE ON SCHEMA auth TO anon;
            GRANT USAGE ON SCHEMA public TO notify_reader;
EOF

        echo "Seed database created (empty): $SEED_NAME"
        echo "  Apply migrations next: ./sb migrate up --target seed"
        echo "  Or rebuild end-to-end:  ./dev.sh recreate-seed"
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
        # Composition: delete-seed + create-seed + migrate up --target seed.
        # Migration 20260427124351 self-drains has_pending residual via an
        # inline CALL worker.process_tasks() in its body — no separate drain
        # step needed here. The auto-rebuild in cli/internal/migrate/migrate.go
        # fires after Up() succeeds and clones the (now-clean) seed into the
        # test template.
        ./dev.sh delete-seed
        ./dev.sh create-seed
        ./sb migrate up --target seed --verbose
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
    'generate-db-documentation' )
        set +e
        check_stamp_guard "./dev.sh generate-db-documentation" "db-docs-passed-sha" "migrations"
        guard_rc=$?
        set -e
        case $guard_rc in
            0) : ;;
            1) exit 0 ;;
            2) exit 1 ;;
        esac

        TEMPLATE_NAME="${POSTGRES_TEST_DB:-statbus_test_template}"
        DOC_DB="statbus_doc_gen_$$"

        TEMPLATE_EXISTS=$(./sb psql -d postgres -t -A -c \
            "SELECT 1 FROM pg_database WHERE datname = '$TEMPLATE_NAME';" 2>/dev/null || echo "0")
        if [ "$TEMPLATE_EXISTS" != "1" ]; then
            echo "Error: Template database '$TEMPLATE_NAME' not found."
            echo "Create it with: ./dev.sh create-test-template"
            exit 1
        fi

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
        # Delete only files in subdirs we regenerate; preserve hand-maintained
        # docs at doc/db/ root (e.g. security.md generated by test 008).
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
            details_file="doc/db/table/${table//\./_}_details.md"

            echo '```sql' > "$base_file"
            doc_psql -c "\d $table" >> "$base_file"
            echo '```' >> "$base_file"

            echo '```sql' > "$details_file"
            doc_psql -c "\d+ $table" >> "$details_file"
            echo '```' >> "$details_file"

            if diff -q "$base_file" "$details_file" >/dev/null; then
              rm "$details_file"
            fi
          fi
        done

        echo "$views" | while read -r view; do
          if [ ! -z "$view" ]; then
            echo "Documenting view $view..."
            base_file="doc/db/view/${view//\./_}.md"
            details_file="doc/db/view/${view//\./_}_details.md"

            echo '```sql' > "$base_file"
            doc_psql -c "\d $view" >> "$base_file"
            echo '```' >> "$base_file"

            echo '```sql' > "$details_file"
            doc_psql -c "\d+ $view" >> "$details_file"
            echo '```' >> "$details_file"

            if diff -q "$base_file" "$details_file" >/dev/null; then
              rm "$details_file"
            fi
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
        mkdir -p "$WORKSPACE/tmp"
        git -C "$WORKSPACE" rev-parse HEAD > "$WORKSPACE/tmp/db-docs-passed-sha"
        echo "DB documentation stamp recorded: $(cat "$WORKSPACE/tmp/db-docs-passed-sha")"
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
        TARGET=${1:-linux/amd64}
        OS=${TARGET%/*}
        ARCH=${TARGET#*/}
        OUTPUT="sb-${OS}-${ARCH}"
        VERSION=$(git describe --tags --always --match 'v[0-9]*' 2>/dev/null | sed 's/^v//' || echo "dev")
        # Full 40-char SHA — see note at line ~51 for rationale.
        COMMIT=$(git rev-parse HEAD 2>/dev/null || echo "unknown")
        LDFLAGS="-s -w -X 'github.com/statisticsnorway/statbus/cli/cmd.version=${VERSION}' -X 'github.com/statisticsnorway/statbus/cli/cmd.commit=${COMMIT}'"
        echo "Building sb ${VERSION} for ${OS}/${ARCH}..."
        cd cli && CGO_ENABLED=0 GOOS=$OS GOARCH=$ARCH go build -trimpath -ldflags "$LDFLAGS" -o "../$OUTPUT" .
        echo "Built: $OUTPUT"
        ls -lh "../$OUTPUT"
      ;;
    'update-seed' )
        # Apply any pending migrations FIRST so the seed reflects the
        # latest schema. Without this, ./sb db seed create dumps the
        # old in-DB schema and the prerelease preflight keeps rejecting
        # the result as "Seed outdated" no matter how many times the
        # user runs this command.
        #
        # ./sb migrate up is idempotent (no-op at HEAD) and serialised by
        # pg_advisory_lock(migrate_up) since R1.1, so it's safe to call
        # unconditionally here.
        #
        # If you want a seed of the CURRENT (pre-migration) state —
        # e.g. to keep around for testing or rollback rehearsal — call
        # the primitive directly: ./sb db seed create.
        ./sb migrate up --verbose
        ./sb db seed create
      ;;
    'test-install' )
        # End-to-end install test using Multipass (Ubuntu VM).
        # Tests the full standalone install path: hardening → install → health check.
        # Writes a stamp file used by ./sb release stable preflight.
        set -euo pipefail

        INSTALL_VERSION="${1:-}"  # optional: use published release instead of local build
        VM_NAME="statbus-install-test"
        STAMP_FILE="$WORKSPACE/tmp/install-test-passed-sha"
        DOMAIN="statbus-test.local"

        echo "=== StatBus Install Test (Multipass) ==="
        echo ""

        # Check Multipass is available
        if ! command -v multipass >/dev/null 2>&1; then
            echo "ERROR: multipass is not installed. Install it: brew install multipass"
            exit 1
        fi

        # Clean up any previous test VM
        if multipass info "$VM_NAME" >/dev/null 2>&1; then
            echo "Cleaning up previous test VM..."
            multipass delete "$VM_NAME" 2>/dev/null || true
            multipass purge 2>/dev/null || true
        fi

        if [ -z "$INSTALL_VERSION" ]; then
            # Build the sb binary for Linux (matching the host architecture).
            # On Apple Silicon, Multipass creates ARM64 VMs.
            HOST_ARCH=$(uname -m)
            case "$HOST_ARCH" in
                x86_64)  BUILD_TARGET="linux/amd64" ;;
                arm64|aarch64) BUILD_TARGET="linux/arm64" ;;
                *) echo "Unsupported architecture: $HOST_ARCH"; exit 1 ;;
            esac
            echo "Building sb for $BUILD_TARGET..."
            ./dev.sh build-sb "$BUILD_TARGET"
        fi

        # Launch fresh Ubuntu 24.04 VM
        echo "Launching Ubuntu 24.04 VM ($VM_NAME)..."
        multipass launch 24.04 --name "$VM_NAME" --cpus 2 --memory 4G --disk 10G --timeout 600

        # Wait for VM to be ready
        echo "Waiting for VM to be ready..."
        multipass exec "$VM_NAME" -- cloud-init status --wait 2>/dev/null || true

        # Transfer files into the VM
        echo "Transferring files..."
        if [ -z "$INSTALL_VERSION" ]; then
            # Transfer the binary matching the local build target
            SB_BINARY="sb-${BUILD_TARGET//\//-}"  # e.g. sb-linux-arm64
            multipass transfer "$SB_BINARY" "$VM_NAME":/tmp/sb
        fi
        multipass transfer ops/setup-ubuntu-lts-24.sh "$VM_NAME":/tmp/setup.sh

        # Create .env.config for standalone mode
        echo "Creating test configuration..."
        cat > /tmp/statbus-test-env-config << 'ENVCONFIG'
DEPLOYMENT_SLOT_NAME=Install Test
DEPLOYMENT_SLOT_CODE=test
DEPLOYMENT_SLOT_PORT_OFFSET=1
CADDY_DEPLOYMENT_MODE=development
SITE_DOMAIN=statbus-test.local
STATBUS_URL=https://statbus-test.local
BROWSER_REST_URL=https://statbus-test.local
SERVER_REST_URL=http://proxy:80
DEBUG=false
PUBLIC_DEBUG=false
UPGRADE_CHANNEL=stable
ENVCONFIG
        multipass transfer /tmp/statbus-test-env-config "$VM_NAME":/tmp/env-config

        # Create a .users.yml with a test admin user
        cat > /tmp/statbus-test-users << 'USERS'
- email: test@statbus.org
  password: test-install-password-2026
  role: admin_user
  display_name: Admin
USERS
        multipass transfer /tmp/statbus-test-users "$VM_NAME":/tmp/users.yml

        # Create hardening config for non-interactive mode
        multipass exec "$VM_NAME" -- sudo bash -c 'cat > /root/.setup-ubuntu.env << EOF
ADMIN_EMAIL="test@statbus.org"
GITHUB_USERS="jhf"
EXTRA_LOCALES=""
CADDY_PLUGINS=""
EOF'

        # Run hardening (non-interactive, installs Docker + prerequisites)
        echo ""
        echo "=== Stage: Hardening ==="
        multipass exec "$VM_NAME" -- sudo bash /tmp/setup.sh --non-interactive 2>&1 | tee tmp/test-install-setup.log
        HARDEN_EXIT=$?
        if [ $HARDEN_EXIT -ne 0 ]; then
            echo "FAILED: Hardening failed (exit $HARDEN_EXIT)"
            echo "VM '$VM_NAME' left running for debugging: multipass shell $VM_NAME"
            exit 1
        fi

        # Create dedicated statbus user (after hardening installs Docker)
        multipass exec "$VM_NAME" -- sudo useradd -m -s /bin/bash -G docker statbus

        # Enable systemd linger so the user's systemd instance starts on first login
        multipass exec "$VM_NAME" -- sudo loginctl enable-linger statbus

        # Set XDG_RUNTIME_DIR in statbus's .profile so that `sudo -i -u statbus`
        # gets a working systemd --user session (PAM doesn't set this for sudo).
        multipass exec "$VM_NAME" -- sudo bash -c \
            'echo "export XDG_RUNTIME_DIR=/run/user/\$(id -u)" >> /home/statbus/.profile'

        # Wait for user manager to be ready after linger enable (~100ms)
        STATBUS_UID=$(multipass exec "$VM_NAME" -- id -u statbus)
        for i in $(seq 1 20); do
            multipass exec "$VM_NAME" -- sudo -u statbus \
                XDG_RUNTIME_DIR=/run/user/$STATBUS_UID \
                systemctl --user is-system-running 2>/dev/null | grep -qE "running|degraded" && break
            sleep 0.1
        done

        # Helper: run a command as the statbus user with a full login shell.
        # sudo -i sources .profile, which sets XDG_RUNTIME_DIR.
        VM_EXEC="multipass exec $VM_NAME -- sudo -i -u statbus"

        # Verify systemctl --user works via sudo -i
        echo "Verifying systemctl --user via sudo -i -u statbus..."
        $VM_EXEC systemctl --user is-system-running || true

        # Set up the install: write commands to a script file and transfer it.
        # Using a script file avoids quoting issues with case statements and
        # nested variables that break when passed via bash -c '...'.
        echo ""
        echo "=== Stage: Install ==="
        if [ -z "$INSTALL_VERSION" ]; then
            cat > /tmp/statbus-test-install.sh << 'SCRIPT'
set -e
mkdir -p ~/statbus
cd ~/statbus
cp /tmp/sb ./sb
chmod +x ./sb
cp /tmp/env-config .env.config
cp /tmp/users.yml .users.yml
STATBUS_MIN_DISK_GB=5 ./sb install --non-interactive --trust-github-user jhf
SCRIPT
        else
            cat > /tmp/statbus-test-install.sh << SCRIPT
set -e
VM_ARCH=\$(uname -m)
case "\$VM_ARCH" in
    x86_64)  GOARCH=amd64 ;;
    arm64|aarch64) GOARCH=arm64 ;;
    *) echo "Unsupported: \$VM_ARCH"; exit 1 ;;
esac
SB_URL="https://github.com/statisticsnorway/statbus/releases/download/${INSTALL_VERSION}/sb-linux-\${GOARCH}"
curl -fsSL "\$SB_URL" -o ~/sb.tmp
chmod +x ~/sb.tmp
git clone --depth 1 --branch ${INSTALL_VERSION} https://github.com/statisticsnorway/statbus.git ~/statbus
mv ~/sb.tmp ~/statbus/sb
cd ~/statbus
cp /tmp/env-config .env.config
cp /tmp/users.yml .users.yml
STATBUS_MIN_DISK_GB=5 ./sb install --non-interactive --trust-github-user jhf
SCRIPT
        fi
        multipass transfer /tmp/statbus-test-install.sh "$VM_NAME":/tmp/install.sh
        multipass exec "$VM_NAME" -- sudo -i -u statbus bash /tmp/install.sh 2>&1 | tee tmp/test-install-install.log
        INSTALL_EXIT=$?
        if [ $INSTALL_EXIT -ne 0 ]; then
            echo "FAILED: Install failed (exit $INSTALL_EXIT)"
            echo "VM '$VM_NAME' left running for debugging: multipass shell $VM_NAME"
            exit 1
        fi

        # Health check — runs from inside the VM.
        # Development mode binds all ports to 127.0.0.1 inside the VM, so the
        # host cannot reach them. HTTP port = 3000 + (DEPLOYMENT_SLOT_PORT_OFFSET * 10).
        echo ""
        echo "=== Stage: Health Check ==="
        HEALTHY=false
        for i in $(seq 1 10); do
            HTTP_CODE=$($VM_EXEC bash -c 'curl -s http://127.0.0.1:3010/rest/ -o /dev/null -w "%{http_code}"' 2>/dev/null || echo "000")
            if echo "$HTTP_CODE" | grep -q "^[23]"; then
                HEALTHY=true
                echo "Health check passed (attempt $i, code=$HTTP_CODE)"
                break
            fi
            echo "Waiting for app... (attempt $i/10, code=$HTTP_CODE)"
            sleep 5
        done

        if [ "$HEALTHY" != "true" ]; then
            echo "FAILED: Health check failed after 10 attempts"
            echo "VM '$VM_NAME' left running for debugging: multipass shell $VM_NAME"
            exit 1
        fi

        # Verify version
        echo ""
        echo "=== Stage: Verify ==="
        $VM_EXEC bash -c 'cd ~/statbus && ./sb --version'

        # Write stamp
        echo ""
        echo "=== PASSED ==="
        mkdir -p "$WORKSPACE/tmp"
        git rev-parse HEAD > "$STAMP_FILE"
        echo "Install test stamp recorded: $(cat "$STAMP_FILE")"

        # Clean up VM
        echo "Cleaning up VM..."
        multipass delete "$VM_NAME"
        multipass purge

        echo "Install test complete."
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
      echo "  recreate-seed                      delete-seed + create-seed + ./sb migrate up --target seed"
      echo "  seed-status                        Compare seed DB to migrations/ at HEAD (set diff)"
      echo "  seed-clone <target>                Clone seed → <target> via pg CREATE DATABASE WITH TEMPLATE"
      echo ""
      echo "Seed publishing & documentation:"
      echo "  update-seed                        Create seed.pg_dump and push to origin/db-seed"
      echo "  dump-seed                          Save database seed for fast restore"
      echo "  list-seeds                         List available seeds"
      echo "  generate-db-documentation          Generate schema docs in doc/db/"
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
      echo "  build-sb [target]                  Cross-compile sb binary (default: linux/amd64)"
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
