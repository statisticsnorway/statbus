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

if ! test -x ./sb; then
    echo "Error: ./sb binary not found. Build it with: cd cli && go build -o ../sb ."
    exit 1
fi

# Set TTY_INPUT to /dev/tty if available (interactive), otherwise /dev/null
if [ -e /dev/tty ]; then
  export TTY_INPUT=/dev/tty
else
  export TTY_INPUT=/dev/null
fi

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
            (cd cli && go build -o ../sb .)
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
        ./dev.sh test all 2>&1 | tee "$TEST_OUTPUT" || true

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

        # Exclude explain/performance baselines — they drift with environment and are regenerated every test run
        if [ $OVERALL_EXIT_CODE -eq 0 ] && git diff --quiet -- ':!test/expected/explain/' ':!test/expected/performance/' 2>/dev/null && git diff --cached --quiet -- ':!test/expected/explain/' ':!test/expected/performance/' 2>/dev/null; then
            mkdir -p "$WORKSPACE/tmp"
            git rev-parse HEAD > "$WORKSPACE/tmp/fast-test-passed-sha"
            echo "Fast test stamp recorded: $(cat "$WORKSPACE/tmp/fast-test-passed-sha")"
        fi

        exit $OVERALL_EXIT_CODE
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
        SNAPSHOT_DIR="$WORKSPACE/migrations/snapshots"

        # Find the latest snapshot file (if any)
        LATEST_SNAPSHOT=$(find "$SNAPSHOT_DIR" -maxdepth 1 -name 'schema_*.pg_dump' -type f 2>/dev/null | sort -V | tail -1 || true)

        if [ -n "$LATEST_SNAPSHOT" ]; then
            SNAPSHOT_VERSION=$(basename "$LATEST_SNAPSHOT" | sed 's/schema_\([0-9]*\)\.pg_dump/\1/')
            SNAPSHOT_LIST="${LATEST_SNAPSHOT%.pg_dump}.pg_list"

            echo "Found snapshot for migration version $SNAPSHOT_VERSION"
            echo "Restoring from snapshot: $LATEST_SNAPSHOT"

            RESTORE_EXIT_CODE=0

            if [ -f "$SNAPSHOT_LIST" ]; then
                echo "Using list file: $SNAPSHOT_LIST"
                docker compose cp "$SNAPSHOT_LIST" db:/tmp/restore.pg_list
                docker compose exec -T db pg_restore -U postgres \
                    --clean \
                    --if-exists \
                    --no-owner \
                    --disable-triggers \
                    --single-transaction \
                    -L /tmp/restore.pg_list \
                    -d "$PGDATABASE" \
                    < "$LATEST_SNAPSHOT" || RESTORE_EXIT_CODE=$?
                docker compose exec -T db rm -f /tmp/restore.pg_list
            else
                docker compose exec -T db pg_restore -U postgres \
                    --clean \
                    --if-exists \
                    --no-owner \
                    --disable-triggers \
                    --single-transaction \
                    -d "$PGDATABASE" \
                    < "$LATEST_SNAPSHOT" || RESTORE_EXIT_CODE=$?
            fi

            if [ $RESTORE_EXIT_CODE -gt 1 ]; then
                echo "Error: pg_restore failed with exit code $RESTORE_EXIT_CODE"
                echo "The database may be in an inconsistent state. Consider running:"
                echo "  ./dev.sh recreate-database"
                exit 1
            elif [ $RESTORE_EXIT_CODE -eq 1 ]; then
                echo "Info: pg_restore completed with warnings (exit code 1) - this is normal for existing objects"
            fi

            echo "Snapshot restored. Running any newer migrations..."
        else
            echo "No snapshot found in $SNAPSHOT_DIR, running all migrations..."
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
        POSTGRES_DIRECTORY="$WORKSPACE/postgres/volumes/db/data"
        if [ -d "$POSTGRES_DIRECTORY" ]; then
          echo "Removing legacy bind-mount directory '$POSTGRES_DIRECTORY'"
          rm -rf "$POSTGRES_DIRECTORY"
        fi
      ;;
    'dump-snapshot' )
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

        SNAPSHOT_DIR="$WORKSPACE/migrations/snapshots"
        SNAPSHOT_DUMP="$SNAPSHOT_DIR/schema_${LATEST_VERSION}.pg_dump"
        SNAPSHOT_LIST="$SNAPSHOT_DIR/schema_${LATEST_VERSION}.pg_list"
        mkdir -p "$SNAPSHOT_DIR"

        echo "Creating snapshot for migration version $LATEST_VERSION..."
        docker compose exec -T db pg_dump -U postgres \
            -Fc \
            --no-owner \
            "$PGDATABASE" > "$SNAPSHOT_DUMP"

        echo "Snapshot dump created: $SNAPSHOT_DUMP"
        ls -lh "$SNAPSHOT_DUMP"

        docker compose cp "$SNAPSHOT_DUMP" db:/tmp/snapshot.pg_dump
        docker compose exec -T db pg_restore -l /tmp/snapshot.pg_dump > "$SNAPSHOT_LIST"
        docker compose exec -T db rm -f /tmp/snapshot.pg_dump

        echo "Snapshot list created: $SNAPSHOT_LIST"
        echo "Edit this file to comment out items that cause restore issues."
      ;;
    'list-snapshots' )
        SNAPSHOT_DIR="$WORKSPACE/migrations/snapshots"
        echo "Available snapshots in $SNAPSHOT_DIR:"
        ls -lh "$SNAPSHOT_DIR"/*.pg_dump 2>/dev/null || echo "  (none - run 'dump-snapshot' to create one)"

        LIST_FILES=$(ls "$SNAPSHOT_DIR"/*.pg_list 2>/dev/null)
        if [ -n "$LIST_FILES" ]; then
            echo ""
            echo "List files (edit these to customize restore):"
            ls -lh "$SNAPSHOT_DIR"/*.pg_list
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

        echo "Creating migrated template database: $TEMPLATE_NAME"

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

        # Create new template by forking from template_statbus (clean, ~9 MB)
        # and running migrations. This avoids copying the main DB (which may be
        # 36+ GB with user-imported data), keeping the template small and test
        # cloning fast (seconds instead of minutes).
        # No need to stop worker/rest — we don't touch the main DB.
        echo "Creating template from template_statbus (clean fork + migrations)..."

        if ! ./sb psql -d postgres -c "
            CREATE DATABASE $TEMPLATE_NAME
            WITH TEMPLATE template_statbus
            OWNER postgres;
        "; then
            echo "Error: Failed to create template database from template_statbus"
            exit 1
        fi

        # Set up roles and schemas that init-db.sh creates for the main DB
        # but are not in template_statbus. Roles are cluster-wide (already exist),
        # but the auth schema and grants must be per-database.
        echo "Setting up schemas and grants for template..."
        ./sb psql -d $TEMPLATE_NAME -v ON_ERROR_STOP=1 <<'EOF'
            CREATE SCHEMA IF NOT EXISTS auth;
            GRANT USAGE ON SCHEMA auth TO authenticated;
            GRANT USAGE ON SCHEMA auth TO anon;
            GRANT USAGE ON SCHEMA public TO notify_reader;
EOF

        # Apply all migrations using the CLI.
        # POSTGRES_APP_DB overrides the CLI's database target.
        # PGDATABASE overrides postgres-variables for .psql migrations.
        echo "Applying migrations to template..."
        if ! POSTGRES_APP_DB=$TEMPLATE_NAME PGDATABASE=$TEMPLATE_NAME ./sb migrate up --verbose; then
            echo "Error: Failed to apply migrations to template database"
            ./sb psql -d postgres -c "DROP DATABASE IF EXISTS $TEMPLATE_NAME;" || true
            exit 1
        fi
        echo "All migrations applied to template."

        # Load JWT secret so auth works in tests
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

        echo "Template created: $TEMPLATE_NAME"
        echo "This template can be used to quickly create isolated test databases."
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
        ./sb types generate
      ;;
    'generate-db-documentation' )
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
        find doc/db -type f -delete

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
        VERSION=$(git describe --tags --always 2>/dev/null || echo "dev")
        COMMIT=$(git rev-parse --short=8 HEAD 2>/dev/null || echo "unknown")
        LDFLAGS="-s -w -X 'github.com/statisticsnorway/statbus/cli/cmd.version=${VERSION}' -X 'github.com/statisticsnorway/statbus/cli/cmd.commit=${COMMIT}'"
        echo "Building sb ${VERSION} for ${OS}/${ARCH}..."
        cd cli && CGO_ENABLED=0 GOOS=$OS GOARCH=$ARCH go build -trimpath -ldflags "$LDFLAGS" -o "../$OUTPUT" .
        echo "Built: $OUTPUT"
        ls -lh "../$OUTPUT"
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
      echo "  create-db-structure                Run migrations (snapshot + incremental)"
      echo "  delete-db-structure                Roll back all migrations"
      echo "  reset-db-structure                 Roll back + re-apply all migrations"
      echo ""
      echo "Testing:"
      echo "  test <all|fast|benchmarks|name>    Run pg_regress tests"
      echo "  test-isolated <name>               Run single test in isolated database"
      echo "  continous-integration-test [branch] [commit]  Full CI test pipeline"
      echo "  diff-fail-first [gui|vim|pipe]     Show diff for first failed test"
      echo "  diff-fail-all [gui|vim|pipe]       Show diffs for all failed tests"
      echo "  make-all-failed-test-results-expected  Accept all test failures"
      echo "  create-test-template               Create template database for test isolation"
      echo "  clean-test-databases [--force]     Drop all test_* databases"
      echo ""
      echo "Snapshots & documentation:"
      echo "  dump-snapshot                      Save database snapshot for fast restore"
      echo "  list-snapshots                     List available snapshots"
      echo "  generate-db-documentation          Generate schema docs in doc/db/"
      echo "  generate-types                     Generate TypeScript types from schema"
      echo ""
      echo "Build:"
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
