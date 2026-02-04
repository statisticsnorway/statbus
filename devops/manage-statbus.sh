#!/bin/bash
# devops/manage-statbus.sh
set -euo pipefail # Exit on error, unbound variable, or any failure in a pipeline

# Check for DEBUG environment variable (accepts "true" or "1")
if [ "${DEBUG:-}" = "true" ] || [ "${DEBUG:-}" = "1" ]; then
  set -x # Print all commands before running them if DEBUG is enabled
fi

# Ensure Homebrew environment is set up for tools like 'shards'
if test -f /etc/profile.d/homebrew.sh; then
  source /etc/profile.d/homebrew.sh
fi

WORKSPACE="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && cd .. && pwd )"
cd $WORKSPACE

# Set TTY_INPUT to /dev/tty if available (interactive), otherwise /dev/null (non-interactive)
if [ -e /dev/tty ]; then
  export TTY_INPUT=/dev/tty
else
  export TTY_INPUT=/dev/null
fi

# Add support for an optional profile as an extra argument for start and stop,
# and when present add the proper `--profile ...` argument.
action=${1:-}
shift || true

set_profile_arg() {
    profile=${1:-}

    # Get the available profiles from Docker Compose
    available_profiles=$(docker compose config --profiles)

    # If no profile is provided (fallback to "all"), display available profiles
    if test -z "$profile"; then
        echo "No profile provided. Available profiles are:"
        echo "$available_profiles"
        exit 1
    else
        # Validate if the provided profile exists
        if ! echo "$available_profiles" | grep -wq "$profile"; then
            echo "Error: Profile '$profile' does not exist in docker compose."
            exit 1
        fi
    fi

    compose_profile_arg="--profile \"$profile\""
    shift || true
}

case "$action" in
    'start' )
        VERSION=$(git describe --always)
        ./devops/dotenv --file .env set VERSION=$VERSION
        ./devops/manage-statbus.sh build-statbus-cli
        ./devops/manage-statbus.sh generate-config
        target_service_or_profile="${1:-}"
        if [ "$target_service_or_profile" = "app" ]; then
            # If the target is 'app', pass it directly as a service to docker compose
            docker compose up --build --detach app
        else
            # Otherwise, use the profile logic
            set_profile_arg "$@"
            eval docker compose $compose_profile_arg up --build --detach
        fi
      ;;
    'stop' )
        target_service_or_profile="${1:-}"
        if [ "$target_service_or_profile" = "app" ]; then
            # If the target is 'app', pass it directly as a service to docker compose
            docker compose down --remove-orphans app
        else
            # Otherwise, use the profile logic
            set_profile_arg "$@"
            eval docker compose $compose_profile_arg down --remove-orphans
        fi
      ;;
    'restart' )
        target_service_or_profile="${1:-}"
        if [ "$target_service_or_profile" = "app" ]; then
            echo "Restarting app service..."
            docker compose down --remove-orphans app
            VERSION=$(git describe --always)
            ./devops/dotenv --file .env set VERSION=$VERSION
            ./devops/manage-statbus.sh build-statbus-cli
            ./devops/manage-statbus.sh generate-config
            docker compose up --build --detach app
            echo "App service restarted."
        else
            # Handles profile logic, including erroring out if no/invalid profile is given
            set_profile_arg "$@" 
            echo "Restarting services in profile: $profile..."
            eval docker compose $compose_profile_arg down --remove-orphans
            VERSION=$(git describe --always)
            ./devops/dotenv --file .env set VERSION=$VERSION
            ./devops/manage-statbus.sh build-statbus-cli
            ./devops/manage-statbus.sh generate-config
            eval docker compose $compose_profile_arg up --build --detach
            echo "Services in profile $profile restarted."
        fi
      ;;
    'logs' )
        eval docker compose logs --follow
      ;;
    'ps' )
        eval docker compose ps
      ;;
    'continous-integration-test' )
        # Validate arguments
        BRANCH=${1:-${BRANCH:-}}
        COMMIT=${2:-${COMMIT:-}}

        # If no branch is provided, use the current branch (local testing case)
        if [ -z "$BRANCH" ]; then
            BRANCH=$(git rev-parse --abbrev-ref HEAD)
            echo "No branch argument provided, using the currently checked-out branch $BRANCH"
        else
            # Ensure the repository is clean before switching branches (no uncommitted changes)
            if ! git diff-index --quiet HEAD --; then
                echo "Error: Repository has uncommitted changes. Please commit or stash changes before switching branches."
                exit 1
            fi

            # Fetch latest changes from the remote,
            # before validating the commit, as it must first
            # be fetched.
            git fetch origin

            # Validate that the commit is provided and non-empty
            if [ -z "$COMMIT" ]; then
                echo "Error: Commit hash must be provided."
                exit 1
            fi

            # Check if the commit exists in the repository
            if ! git cat-file -e "$COMMIT" 2>/dev/null; then
                echo "Error: Commit '$COMMIT' is invalid or not found."
                exit 1
            fi

            # Log the branch and commit being used for debugging
            echo "Checking out branch '$BRANCH' at commit '$COMMIT'"

            # Create or reset the local branch with the given name, using the specified commit
            git checkout -B "$BRANCH" "$COMMIT"
        fi

        ./devops/manage-statbus.sh generate-config
        ./devops/manage-statbus.sh delete-db

        # Proceed with the rest of the workflow
        ./devops/manage-statbus.sh create-db > /dev/null

        # Ensure delete-db runs no matter what
        trap './devops/manage-statbus.sh delete-db > /dev/null' EXIT

        # Run tests and capture output
        TEST_OUTPUT=$(mktemp)
        ./devops/manage-statbus.sh test all 2>&1 | tee "$TEST_OUTPUT" || true

        # Check if the test output indicates failure
        if grep -q "not ok" "$TEST_OUTPUT" || grep -q "of .* tests failed" "$TEST_OUTPUT"; then
            echo "One or more tests failed."
            echo "Test summary:"
            grep -A 20 "======================" "$TEST_OUTPUT"

            # Display the diff with color using delta (Rust tool)
            if command -v delta >/dev/null 2>&1; then
                echo "Showing the color-coded diff:"
                docker compose exec --workdir /statbus db cat /statbus/test/regression.diffs | delta
            else
                echo "Error: 'delta' tool is not installed. You can install it with:"
                echo "  brew install git-delta"

                echo "Showing raw diff:"
                docker compose exec --workdir /statbus db cat /statbus/test/regression.diffs
            fi

            # Exit with failure status
            exit 1
        else
            echo "All tests passed successfully."
        fi
      ;;
    'test' )
        eval $(./devops/manage-statbus.sh postgres-variables)
        
        # Extract PostgreSQL major version from Dockerfile
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

        # Store original arguments
        ORIGINAL_ARGS=("$@")

        # Check for --update-expected flag and filter it out
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
        
        # Check if no arguments were provided
        if [ ${#TEST_ARGS[@]} -eq 0 ]; then
            echo "Available tests:"
            echo "all"
            echo "fast"
            echo "failed"
            basename -s .sql "$PG_REGRESS_DIR/sql"/*.sql
            exit 0
        fi
        
        # Check for special keywords
        if [ "${TEST_ARGS[0]}" = "all" ]; then
            # Get all tests
            ALL_TESTS=$(basename -s .sql "$PG_REGRESS_DIR/sql"/*.sql)
            
            # Process exclusions (tests starting with -)
            TEST_BASENAMES=""
            for test in $ALL_TESTS; do
                exclude=false
                for arg in "${TEST_ARGS[@]:1}"; do  # Skip the first arg which is "all"
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
            # Get all tests
            ALL_TESTS=$(basename -s .sql "$PG_REGRESS_DIR/sql"/*.sql)

            # Process exclusions
            TEST_BASENAMES=""
            for test in $ALL_TESTS; do
                exclude=false

                # Exclude slow tests (4xx series are large data imports)
                if [[ "$test" == 4* ]]; then
                    exclude=true
                fi

                # Check against additional user-provided exclusions, if any
                if [ "$exclude" = "false" ]; then
                    for arg in "${TEST_ARGS[@]:1}"; do  # Skip the first arg which is "fast"
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
            # Get failed tests
            FAILED_TESTS=$(grep -E '^not ok' $WORKSPACE/test/regression.out | sed -E 's/not ok[[:space:]]+[0-9]+[[:space:]]+- ([^[:space:]]+).*/\1/')
            
            # Process exclusions
            TEST_BASENAMES=""
            for test in $FAILED_TESTS; do
                exclude=false
                for arg in "${TEST_ARGS[@]:1}"; do  # Skip the first arg which is "failed"
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
            # Just use the provided test names, filtering out exclusions
            TEST_BASENAMES=""
            for arg in "${TEST_ARGS[@]}"; do
                if [[ "$arg" != -* ]]; then
                    TEST_BASENAMES="$TEST_BASENAMES $arg"
                fi
            done
        fi

        # Validate that all requested tests exist
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
            echo "  fast   - Run all tests except 4xx (large imports)"
            echo "  failed - Re-run previously failed tests"
            echo ""
            echo "Individual tests:"
            basename -s .sql "$PG_REGRESS_DIR/sql"/*.sql | sed 's/^/  /'
            exit 1
        fi

        # Separate tests into shared (non-4xx) and isolated (4xx) categories
        # 4xx tests use COMMIT and need their own database to avoid polluting state
        SHARED_TESTS=""
        ISOLATED_TESTS=""
        
        for test_basename in $TEST_BASENAMES; do
            expected_file="$PG_REGRESS_DIR/expected/$test_basename.out"
            if [ ! -f "$expected_file" ] && [ -f "$PG_REGRESS_DIR/sql/$test_basename.sql" ]; then
                echo "Warning: Expected output file $expected_file not found. Creating an empty placeholder."
                touch "$expected_file"
            fi
            
            # Categorize: 4xx tests run isolated, others run shared
            if [[ "$test_basename" == 4* ]]; then
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
        
        # Run shared tests together on the main database (fast, uses BEGIN/ROLLBACK)
        if [ -n "$SHARED_TESTS" ]; then
            echo "=== Running shared tests (BEGIN/ROLLBACK isolation) ==="
            docker compose exec --workdir "/statbus" db \
                $PG_REGRESS $debug_arg \
                --use-existing \
                --bindir="/usr/lib/postgresql/$POSTGRESQL_MAJOR/bin" \
                --inputdir=$CONTAINER_REGRESS_DIR \
                --outputdir=$CONTAINER_REGRESS_DIR \
                --dbname=$PGDATABASE \
                --user=$PGUSER \
                $SHARED_TESTS || OVERALL_EXIT_CODE=$?
        fi
        
        # Run isolated tests each in their own database from template
        if [ -n "$ISOLATED_TESTS" ]; then
            echo ""
            echo "=== Running isolated tests (database-per-test from template) ==="
            for test_basename in $ISOLATED_TESTS; do
                update_arg=""
                if [ "$update_expected" = "true" ]; then
                    update_arg="--update-expected"
                fi
                ./devops/manage-statbus.sh test-isolated "$test_basename" $update_arg || OVERALL_EXIT_CODE=$?
            done
        fi

        # Handle --update-expected for shared tests (isolated tests handle it themselves)
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
        
        exit $OVERALL_EXIT_CODE
    ;;
    'diff-fail-first' )
      if [ ! -f "$WORKSPACE/test/regression.out" ]; then
          echo "Error: File $WORKSPACE/test/regression.out not found."
          echo "Run tests first: ./devops/manage-statbus.sh test fast"
          exit 1
      fi
      
      if [ ! -r "$WORKSPACE/test/regression.out" ]; then
          echo "Error: Cannot read $WORKSPACE/test/regression.out"
          exit 1
      fi

      # Extract the full test name from the regression output (use -a to force text mode)
      test_line=$(grep -a -E '^not ok' "$WORKSPACE/test/regression.out" | head -n 1)
      
      # Check if grep failed to find proper test results
      if [[ "$test_line" =~ ^Binary\ file.*matches$ ]]; then
          echo "Error: Cannot parse test results. The regression.out file may be corrupted."
          echo "Try running tests again: ./devops/manage-statbus.sh test fast"
          exit 1
      fi
      
      if [ -n "$test_line" ]; then
          # Extract the full test name (e.g., "01_load_web_examples")
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
                  # Note the pipe from /dev/tty to avoid the diff alias running an interactive program.
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
          echo "Run tests first: ./devops/manage-statbus.sh test fast"
          exit 1
      fi
      
      if [ ! -r "$WORKSPACE/test/regression.out" ]; then
          echo "Error: Cannot read $WORKSPACE/test/regression.out"
          exit 1
      fi

      ui_choice=${1:-pipe} # Get UI choice from the first argument to diff-fail-all, default to pipe
      line_limit=${2:-}
      
      # Check if grep will work properly (use -a to force text mode)
      first_line=$(grep -a -E '^not ok' "$WORKSPACE/test/regression.out" | head -n 1)
      if [[ "$first_line" =~ ^Binary\ file.*matches$ ]]; then
          echo "Error: Cannot parse test results. The regression.out file may be corrupted."
          echo "Try running tests again: ./devops/manage-statbus.sh test fast"
          exit 1
      fi
      
      if [ -z "$first_line" ]; then
          echo "No failing tests found in regression.out"
          exit 0
      fi

      # Use process substitution to avoid running the loop in a subshell,
      # which can have subtle side effects on variable scope and signal handling.
      while read test_line; do
          # Extract the full test name (e.g., "01_load_web_examples")
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
                  # Note the pipe from /dev/tty to avoid the diff alias running an interactive program.
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
            echo "Run tests first: ./devops/manage-statbus.sh test fast"
            exit 1
        fi
        
        if [ ! -r "$WORKSPACE/test/regression.out" ]; then
            echo "Error: Cannot read $WORKSPACE/test/regression.out"
            exit 1
        fi

        grep -a -E '^not ok' "$WORKSPACE/test/regression.out" | while read -r test_line; do
            # Extract the full test name (e.g., "01_load_web_examples")
            test=$(echo "$test_line" | sed -E 's/not ok[[:space:]]+[0-9]+[[:space:]]+- ([^[:space:]]+).*/\1/')
            if [ -f "$WORKSPACE/test/results/$test.out" ]; then
                echo "Copying results to expected for test: $test"
                cp -f "$WORKSPACE/test/results/$test.out" "$WORKSPACE/test/expected/$test.out"
            else
                echo "Warning: No results file found for test: $test"
            fi
        done
    ;;
    'build-statbus-cli' )
        pushd cli
          shards build
        popd
      ;;
    'create-db-structure' )
        eval $(./devops/manage-statbus.sh postgres-variables)
        SNAPSHOT_DIR="$WORKSPACE/migrations/snapshots"
        
        # Build the CLI tool first
        pushd cli
          shards build statbus
        popd
        
        # Find the latest snapshot file (if any)
        # Use find instead of ls to avoid glob expansion issues with set -e pipefail
        LATEST_SNAPSHOT=$(find "$SNAPSHOT_DIR" -maxdepth 1 -name 'schema_*.pg_dump' -type f 2>/dev/null | sort -V | tail -1 || true)
        
        if [ -n "$LATEST_SNAPSHOT" ]; then
            # Extract version from filename (schema_20260126221107.pg_dump -> 20260126221107)
            SNAPSHOT_VERSION=$(basename "$LATEST_SNAPSHOT" | sed 's/schema_\([0-9]*\)\.pg_dump/\1/')
            SNAPSHOT_LIST="${LATEST_SNAPSHOT%.pg_dump}.pg_list"
            
            echo "Found snapshot for migration version $SNAPSHOT_VERSION"
            echo "Restoring from snapshot: $LATEST_SNAPSHOT"
            
            # Restore snapshot using pg_restore
            # --clean --if-exists: Drop objects before recreating (safe with if-exists)
            # --no-owner: Don't try to set ownership (roles from init-db.sh)
            # --disable-triggers: Disable triggers/constraints during data load (as superuser)
            # --single-transaction: All-or-nothing restore
            # -L: Use list file for selective restore (if available)
            # Note: List file must be passed via volume mount since it's on host
            # pg_restore exit codes:
            #   0 = success
            #   1 = warnings only (e.g., "relation already exists") - acceptable
            #   >1 = critical errors (corrupt dump, connection failure, etc.) - FAIL FAST
            RESTORE_EXIT_CODE=0
            
            if [ -f "$SNAPSHOT_LIST" ]; then
                echo "Using list file: $SNAPSHOT_LIST"
                # Copy list file to container, restore, then clean up
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
            
            # Check restore result
            if [ $RESTORE_EXIT_CODE -gt 1 ]; then
                echo "Error: pg_restore failed with exit code $RESTORE_EXIT_CODE"
                echo "This indicates a critical restore failure (corrupt dump, connection error, disk space, etc.)"
                echo "The database may be in an inconsistent state. Consider running:"
                echo "  ./devops/manage-statbus.sh recreate-database"
                exit 1
            elif [ $RESTORE_EXIT_CODE -eq 1 ]; then
                echo "Info: pg_restore completed with warnings (exit code 1) - this is normal for existing objects"
            fi
            
            echo "Snapshot restored. Running any newer migrations..."
        else
            echo "No snapshot found in $SNAPSHOT_DIR, running all migrations..."
        fi
        
        # Run migrations (will only apply migrations newer than what's in db.migration table)
        ./cli/bin/statbus migrate up all -v
        
        # Load secrets after migrations because:
        # 1. auth.secrets table must exist (created by migration 20240102100000)
        # 2. Functions that create users need JWT secret to generate API keys
        # 3. Doing it here ensures both 'create-db' and direct 'create-db-structure' calls work
        JWT_SECRET=$(./devops/dotenv --file .env.credentials get JWT_SECRET)
        DEPLOYMENT_SLOT_CODE=$(./devops/dotenv --file .env.config get DEPLOYMENT_SLOT_CODE)
        PGDATABASE=statbus_${DEPLOYMENT_SLOT_CODE:-dev}
        ./devops/manage-statbus.sh psql -c "INSERT INTO auth.secrets (key, value, description) VALUES ('jwt_secret', '$JWT_SECRET', 'JWT signing secret') ON CONFLICT (key) DO UPDATE SET value = EXCLUDED.value, updated_at = clock_timestamp();"
        ./devops/manage-statbus.sh psql -c "ALTER DATABASE $PGDATABASE SET app.settings.deployment_slot_code TO '$DEPLOYMENT_SLOT_CODE';"
      ;;
    'delete-db-structure' )
        pushd cli
          shards build statbus && ./bin/statbus migrate down all -v
        popd
      ;;
    'reset-db-structure' )
        pushd cli
          shards build statbus
        popd
        ./cli/bin/statbus migrate down all
        ./cli/bin/statbus migrate up
        ./devops/manage-statbus.sh create-users
      ;;
    'create-db' )
        ./devops/manage-statbus.sh start all_except_app
        ./devops/manage-statbus.sh create-db-structure
        ./devops/manage-statbus.sh create-users
        ./devops/manage-statbus.sh create-test-template
      ;;
    'recreate-database' )
        echo "Recreate the backend with the lastest database structures"
        ./devops/manage-statbus.sh delete-db
        ./devops/manage-statbus.sh create-db
      ;;
    'delete-db' )
        ./devops/manage-statbus.sh stop all
        # Define the directory path for PostgreSQL volume
        POSTGRES_DIRECTORY="$WORKSPACE/postgres/volumes/db/data"

        # Check and remove PostgreSQL directory if it exists
        if [ -d "$POSTGRES_DIRECTORY" ]; then
          if ! test -r "$POSTGRES_DIRECTORY" || ! test -w "$POSTGRES_DIRECTORY" || ! test -x "$POSTGRES_DIRECTORY"; then
            echo "Removing '$POSTGRES_DIRECTORY' with sudo"
            sudo rm -rf "$POSTGRES_DIRECTORY"
          else
            echo "Removing '$POSTGRES_DIRECTORY'"
            rm -rf "$POSTGRES_DIRECTORY"
          fi
        fi
      ;;
    'create-users' )
        ./cli/bin/statbus manage create-users -v
      ;;
    'dump-snapshot' )
        eval $(./devops/manage-statbus.sh postgres-variables)
        
        # Verify database is running before attempting dump
        if ! ./devops/manage-statbus.sh is-db-running; then
            echo "Error: Database is not running. Start with: ./devops/manage-statbus.sh start all"
            exit 1
        fi
        
        # Get latest migration version from database
        LATEST_VERSION=$(echo "SELECT version FROM db.migration ORDER BY version DESC LIMIT 1;" \
            | ./devops/manage-statbus.sh psql -t -A)
        
        if [ -z "$LATEST_VERSION" ]; then
            echo "Error: No migrations found in database"
            exit 1
        fi
        
        SNAPSHOT_DIR="$WORKSPACE/migrations/snapshots"
        SNAPSHOT_DUMP="$SNAPSHOT_DIR/schema_${LATEST_VERSION}.pg_dump"
        SNAPSHOT_LIST="$SNAPSHOT_DIR/schema_${LATEST_VERSION}.pg_list"
        mkdir -p "$SNAPSHOT_DIR"
        
        echo "Creating snapshot for migration version $LATEST_VERSION..."
        echo "This includes all schema and data from the current database."
        
        # Use custom format (-Fc) with default gzip compression
        # --no-owner: Skip ownership commands (roles created by init-db.sh)
        # Note: -Fc includes gzip compression by default
        # Note: We include ACLs (GRANTs) since they're essential for RLS policies
        docker compose exec -T db pg_dump -U postgres \
            -Fc \
            --no-owner \
            "$PGDATABASE" > "$SNAPSHOT_DUMP"
        
        echo "Snapshot dump created: $SNAPSHOT_DUMP"
        ls -lh "$SNAPSHOT_DUMP"
        
        # Generate list file for selective restore
        # This can be edited to comment out problematic items
        # Use container's pg_restore to ensure version compatibility with the dump
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
        
        # Also show list files
        LIST_FILES=$(ls "$SNAPSHOT_DIR"/*.pg_list 2>/dev/null)
        if [ -n "$LIST_FILES" ]; then
            echo ""
            echo "List files (edit these to customize restore):"
            ls -lh "$SNAPSHOT_DIR"/*.pg_list
        fi
        
        if ./devops/manage-statbus.sh is-db-running 2>/dev/null; then
            LATEST_DB_VERSION=$(echo "SELECT version FROM db.migration ORDER BY version DESC LIMIT 1;" \
                | ./devops/manage-statbus.sh psql -t -A 2>/dev/null)
            echo ""
            echo "Current database migration version: ${LATEST_DB_VERSION:-not available}"
        fi
      ;;
    'is-db-running' )
        # Check if database container is running and accepting connections
        docker compose exec -T db pg_isready -U postgres > /dev/null 2>&1
      ;;
    'clean-test-databases' )
        # Remove all test databases (those starting with 'test_')
        eval $(./devops/manage-statbus.sh postgres-variables)
        
        echo "Finding test databases to clean up..."
        TEST_DBS=$(./devops/manage-statbus.sh psql -d postgres -t -A -c "
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
        
        # Ask for confirmation unless --force is passed
        if [ "${1:-}" != "--force" ]; then
            echo ""
            read -p "Drop all these databases? [y/N] " -r < "$TTY_INPUT"
            if [[ ! $REPLY =~ ^[Yy]$ ]]; then
                echo "Cancelled."
                exit 0
            fi
        fi
        
        # Drop each test database, tracking failures
        FAILED_DBS=""
        DROPPED_COUNT=0
        while read -r db; do
            if [ -n "$db" ]; then
                echo "Dropping: $db"
                if ./devops/manage-statbus.sh psql -d postgres -c "DROP DATABASE IF EXISTS \"$db\";" 2>&1; then
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
        eval $(./devops/manage-statbus.sh postgres-variables)
        TEMPLATE_NAME="template_statbus_migrated"
        
        echo "Creating migrated template database: $TEMPLATE_NAME"
        
        # Check if template already exists
        TEMPLATE_EXISTS=$(./devops/manage-statbus.sh psql -d postgres -t -A -c \
            "SELECT 1 FROM pg_database WHERE datname = '$TEMPLATE_NAME';" 2>/dev/null || echo "0")
        
        if [ "$TEMPLATE_EXISTS" = "1" ]; then
            echo "Existing template found, removing it..."
            
            # Terminate connections to template - OK if none exist
            ./devops/manage-statbus.sh psql -d postgres -c "
                SELECT pg_terminate_backend(pid) 
                FROM pg_stat_activity 
                WHERE datname = '$TEMPLATE_NAME';
            " || true
            
            # Unmark as template - MUST succeed if template exists
            if ! ./devops/manage-statbus.sh psql -d postgres -c "
                UPDATE pg_database SET datistemplate = false WHERE datname = '$TEMPLATE_NAME';
            "; then
                echo "Error: Failed to unmark template database. Check permissions."
                exit 1
            fi
            
            # Drop template - MUST succeed
            if ! ./devops/manage-statbus.sh psql -d postgres -c "DROP DATABASE $TEMPLATE_NAME;"; then
                echo "Error: Failed to drop existing template database."
                echo "There may be active connections. Check with:"
                echo "  ./devops/manage-statbus.sh psql -c \"SELECT * FROM pg_stat_activity WHERE datname = '$TEMPLATE_NAME';\""
                exit 1
            fi
        fi
        
        # Create new template from current database
        # Note: This requires no other connections to the source database
        echo "Creating template from $PGDATABASE (this requires exclusive access)..."
        
        # Stop services that hold connections (worker reconnects automatically)
        echo "Stopping worker and rest services temporarily..."
        if ! docker compose stop worker rest 2>&1; then
            echo "Warning: Could not stop worker/rest services. They may not be running."
        fi
        
        # Terminate any remaining connections to the source database (except our own)
        ./devops/manage-statbus.sh psql -d postgres -c "
            SELECT pg_terminate_backend(pid) 
            FROM pg_stat_activity 
            WHERE datname = '$PGDATABASE' 
            AND pid <> pg_backend_pid();
        " || true
        
        # Create the template - MUST succeed
        if ! ./devops/manage-statbus.sh psql -d postgres -c "
            CREATE DATABASE $TEMPLATE_NAME 
            WITH TEMPLATE $PGDATABASE 
            OWNER postgres;
        "; then
            echo "Error: Failed to create template database from $PGDATABASE"
            echo "There may be active connections to the source database. Check with:"
            echo "  ./devops/manage-statbus.sh psql -c \"SELECT * FROM pg_stat_activity WHERE datname = '$PGDATABASE';\""
            # Try to restart services before exiting
            docker compose start worker rest 2>/dev/null || true
            exit 1
        fi
        
        # Restart the services - MUST succeed for system to be functional
        echo "Restarting worker and rest services..."
        if ! docker compose start worker rest; then
            echo "Error: Failed to restart worker/rest services!"
            echo "The template was created, but services are down. Manually restart with:"
            echo "  docker compose start worker rest"
            exit 1
        fi
        
        # Mark as template and prevent connections (so it stays clean)
        if ! ./devops/manage-statbus.sh psql -d postgres -c "
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
        # Run a single test in an isolated database created from template
        # Usage: ./devops/manage-statbus.sh test-isolated <test_name> [--update-expected]
        eval $(./devops/manage-statbus.sh postgres-variables)
        TEMPLATE_NAME="template_statbus_migrated"
        
        # Parse arguments
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
            echo "Usage: ./devops/manage-statbus.sh test-isolated <test_name> [--update-expected]"
            exit 1
        fi
        
        # Check if this is a group name (all, fast, failed) - these don't work with test-isolated
        if [ "$TEST_NAME" = "all" ] || [ "$TEST_NAME" = "fast" ] || [ "$TEST_NAME" = "failed" ]; then
            echo "Error: '$TEST_NAME' is a test group, not an individual test."
            echo "Use './devops/manage-statbus.sh test $TEST_NAME' to run test groups."
            echo ""
            echo "Usage: ./devops/manage-statbus.sh test-isolated <test_name> [--update-expected]"
            exit 1
        fi
        
        # Check if test file exists
        PG_REGRESS_DIR="$WORKSPACE/test"
        if [ ! -f "$PG_REGRESS_DIR/sql/$TEST_NAME.sql" ]; then
            echo "Error: Test '$TEST_NAME' not found."
            echo ""
            echo "Available tests:"
            basename -s .sql "$PG_REGRESS_DIR/sql"/*.sql | sed 's/^/  /'
            exit 1
        fi
        
        # Sanitize test name to alphanumeric and underscore only (prevent SQL injection)
        SAFE_TEST_NAME=$(echo "$TEST_NAME" | tr -cd '[:alnum:]_')
        
        # Generate unique database name using sanitized test name and PID
        TEST_DB="test_${SAFE_TEST_NAME}_$$"
        
        # Extract PostgreSQL major version from Dockerfile
        POSTGRESQL_MAJOR=$(grep -E "^ARG postgresql_major=" "$WORKSPACE/postgres/Dockerfile" | cut -d= -f2)
        PG_REGRESS="/usr/lib/postgresql/$POSTGRESQL_MAJOR/lib/pgxs/src/test/regress/pg_regress"
        PG_REGRESS_DIR="$WORKSPACE/test"
        CONTAINER_REGRESS_DIR="/statbus/test"
        
        # Check if template exists
        if ! ./devops/manage-statbus.sh psql -d postgres -t -A -c "SELECT 1 FROM pg_database WHERE datname = '$TEMPLATE_NAME';" 2>/dev/null | grep -q 1; then
            echo "Error: Template database '$TEMPLATE_NAME' not found."
            echo "Run './devops/manage-statbus.sh create-db' or './devops/manage-statbus.sh create-test-template' first."
            exit 1
        fi
        
        echo "=== Running isolated test: $TEST_NAME ==="
        echo "Creating isolated test database: $TEST_DB from template $TEMPLATE_NAME"
        
        # Setup cleanup trap (runs on exit, including Ctrl+C)
        # Default: PERSIST=false (clean up test databases)
        cleanup_test_db() {
            local exit_code=$?
            if [ "${PERSIST:-false}" = "true" ]; then
                echo "PERSIST=true: Keeping test database: $TEST_DB"
                return $exit_code
            fi
            if [ -n "$TEST_DB" ]; then
                echo "Cleaning up test database: $TEST_DB"
                if ! ./devops/manage-statbus.sh psql -d postgres -c "DROP DATABASE IF EXISTS \"$TEST_DB\";" 2>&1; then
                    echo "Warning: Failed to drop test database '$TEST_DB'"
                    echo "It may have active connections. Clean up manually with:"
                    echo "  ./devops/manage-statbus.sh psql -d postgres -c \"DROP DATABASE IF EXISTS \\\"$TEST_DB\\\";\""
                fi
            fi
            return $exit_code
        }
        trap cleanup_test_db EXIT
        
        # Use advisory lock to prevent race conditions when multiple tests access template
        # Lock ID 59328 is arbitrary but consistent for this operation
        # CRITICAL: All operations must be in ONE session - advisory locks are session-scoped
        # The lock is held until explicitly released (or session ends)
        if ! ./devops/manage-statbus.sh psql -d postgres -v ON_ERROR_STOP=1 <<EOF
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
        
        # Run the test against the isolated database
        debug_arg=""
        if [ "${DEBUG:-}" = "true" ]; then
            debug_arg="--debug"
        fi
        
        # Ensure expected file exists
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
        
        # Handle --update-expected
        if [ "$UPDATE_EXPECTED" = "true" ]; then
            result_file="$PG_REGRESS_DIR/results/$TEST_NAME.out"
            if [ -f "$result_file" ]; then
                echo "  -> Updating expected output for $TEST_NAME"
                cp "$result_file" "$expected_file"
            fi
        fi
        
        # Cleanup happens via trap
        exit $TEST_EXIT_CODE
      ;;
     'generate-config' )
        if [ ! -f .env ]; then
            echo "Bootstrapping new configuration because .env file is missing."

            slot_offset=1 # Default value
            if [ -t 0 ]; then
                # Prompt for the port offset if running interactively
                read -p "Enter deployment slot port offset (e.g., 1, 2, ...) [1]: " user_slot_offset
                slot_offset=${user_slot_offset:-1}
            else
                echo "Running non-interactively, using default deployment slot port offset: ${slot_offset}"
            fi

            # Update .env.config so the Crystal app uses the same value
            echo "Setting DEPLOYMENT_SLOT_PORT_OFFSET=${slot_offset} in .env.config for generation..."
            ./devops/dotenv --file .env.config set DEPLOYMENT_SLOT_PORT_OFFSET "${slot_offset}"

            # Calculate CADDY_DB_PORT based on the logic in cli/src/manage.cr
            # and export it so the Crystal app can initialize.
            base_port=3000
            slot_multiplier=10
            port_offset=$((base_port + slot_offset * slot_multiplier))
            db_port=$((port_offset + 4))

            echo "Temporarily exporting CADDY_DB_PORT=$db_port for initialization."
            export CADDY_DB_PORT=$db_port
        fi

        ./cli/bin/statbus manage generate-config
        ;;
     'postgres-variables' )
        SITE_DOMAIN=$(./devops/dotenv --file .env get SITE_DOMAIN || echo "local.statbus.org")
        CADDY_DEPLOYMENT_MODE=$(./devops/dotenv --file .env get CADDY_DEPLOYMENT_MODE || echo "development")
        PGDATABASE=$(./devops/dotenv --file .env get POSTGRES_APP_DB)
        # Preserve the USER if already setup, to allow overrides.
        PGUSER=${PGUSER:-$(./devops/dotenv --file .env get POSTGRES_ADMIN_USER)}
        PGPASSWORD=$(./devops/dotenv --file .env get POSTGRES_ADMIN_PASSWORD)
        
        # PostgreSQL connection configuration
        # Two separate ports: plaintext (default) and TLS (with TLS=1)
        PGHOST=$SITE_DOMAIN
        
        # Check if TLS is explicitly requested (for testing production-like connections)
        if [ "${TLS:-}" = "1" ] || [ "${TLS:-}" = "true" ]; then
            # TLS mode - use dedicated TLS port with PostgreSQL 17+ TLS/SNI configuration
            PGPORT=$(./devops/dotenv --file .env get CADDY_DB_TLS_PORT)
            # Use Caddy-compatible TLS (industry standard direct TLS negotiation)
            PGSSLNEGOTIATION=direct
            # Require SSL/TLS but don't verify certificate (self-signed in dev)
            PGSSLMODE=require
            # Send PGHOST as SNI for Caddy's layer4 routing
            PGSSLSNI=1
            cat <<EOS
export PGHOST=$PGHOST PGPORT=$PGPORT PGDATABASE=$PGDATABASE PGUSER=$PGUSER PGPASSWORD=$PGPASSWORD PGSSLMODE=$PGSSLMODE PGSSLNEGOTIATION=$PGSSLNEGOTIATION PGSSLSNI=$PGSSLSNI
EOS
        else
            # Default: plaintext on dedicated plaintext port (works for local, SSH tunnel, etc.)
            PGPORT=$(./devops/dotenv --file .env get CADDY_DB_PORT)
            PGSSLMODE=disable
            cat <<EOS
export PGHOST=$PGHOST PGPORT=$PGPORT PGDATABASE=$PGDATABASE PGUSER=$PGUSER PGPASSWORD=$PGPASSWORD PGSSLMODE=$PGSSLMODE
EOS
        fi
      ;;
     'psql' )
        eval $(./devops/manage-statbus.sh postgres-variables)
        # The local psql is always tried first, as it has access to files
        # used for copying in data.
        # Set DOCKER_PSQL=1 to force using Docker psql (useful for testing).
        if [ -z "${DOCKER_PSQL:-}" ] && $(which psql > /dev/null); then
          psql "$@"
        else
          if test -t 0 && test -t 1 && test ! -p /dev/stdin && test ! -f /dev/stdin; then
            # Interactive mode - use default TTY allocation
            docker compose exec -w /statbus -e PGPASSWORD -u postgres db psql -U $PGUSER $PGDATABASE "$@"
          else
            # Non-interactive mode - explicitly disable TTY allocation
            docker compose exec -T -w /statbus -e PGPASSWORD -u postgres db psql -U $PGUSER $PGDATABASE "$@"
          fi
        fi
      ;;
     'generate-db-documentation' )
        # Create documentation directories and clean out old files
        mkdir -p doc/db/table doc/db/view doc/db/function
        echo "Cleaning documentation files..."
        find doc/db -type f -delete

        # Get list of all tables, materialized views, and regular views from specified schemas
        tables=$(./devops/manage-statbus.sh psql -t <<'EOS'
          SELECT schemaname || '.' || tablename
          FROM pg_catalog.pg_tables
          WHERE schemaname IN ('admin', 'db', 'lifecycle_callbacks', 'public', 'auth')
          UNION ALL
          SELECT schemaname || '.' || matviewname
          FROM pg_catalog.pg_matviews
          WHERE schemaname IN ('admin', 'db', 'lifecycle_callbacks', 'public', 'auth')
          ORDER BY 1;
EOS
)

        views=$(./devops/manage-statbus.sh psql -t <<'EOS'
          SELECT schemaname || '.' || viewname
          FROM pg_catalog.pg_views
          WHERE schemaname IN ('admin', 'db', 'lifecycle_callbacks', 'public', 'auth')
            AND viewname NOT LIKE 'hypopg_%'
            AND viewname NOT LIKE 'pg_stat_%'
          ORDER BY 1;
EOS
)

        # Document each table
        echo "$tables" | while read -r table; do
          if [ ! -z "$table" ]; then
            echo "Documenting table $table..."
            # Create temporary files
            base_file="doc/db/table/${table//\./_}.md"
            details_file="doc/db/table/${table//\./_}_details.md"

            # Generate both overview and details.
            echo '```sql' > "$base_file"
            ./devops/manage-statbus.sh psql -c "\d $table" >> "$base_file"
            echo '```' >> "$base_file"

            echo '```sql' > "$details_file"
            ./devops/manage-statbus.sh psql -c "\d+ $table" >> "$details_file"
            echo '```' >> "$details_file"

            # Compare files and remove details if they're identical
            if diff -q "$base_file" "$details_file" >/dev/null; then
              rm "$details_file"
            fi
          fi
        done

        # Document each view
        echo "$views" | while read -r view; do
          if [ ! -z "$view" ]; then
            echo "Documenting view $view..."
            # Create temporary files
            base_file="doc/db/view/${view//\./_}.md"
            details_file="doc/db/view/${view//\./_}_details.md"

            # Generate both overview and details.
            echo '```sql' > "$base_file"
            ./devops/manage-statbus.sh psql -c "\d $view" >> "$base_file"
            echo '```' >> "$base_file"

            echo '```sql' > "$details_file"
            ./devops/manage-statbus.sh psql -c "\d+ $view" >> "$details_file"
            echo '```' >> "$details_file"

            # Compare files and remove details if they're identical
            if diff -q "$base_file" "$details_file" >/dev/null; then
              rm "$details_file"
            fi
          fi
        done

        # Get and document functions
        functions=$(./devops/manage-statbus.sh psql -t <<'EOS'
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
          WHERE n.nspname IN ('admin', 'db', 'lifecycle_callbacks', 'public', 'auth')
            AND p.prokind != 'a'  -- Exclude aggregate functions
            -- Exclude functions belonging to extensions (they are system/library functions)
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
            # Create function documentation
            base_file="doc/db/function/${func//\./_}.md"

            # Generate function definition
            echo '```sql' > "$base_file"
            ./devops/manage-statbus.sh psql -c "\sf $func" >> "$base_file"
            echo '```' >> "$base_file"
          fi
        done

        echo "Database documentation generated in doc/db/{table,view,function}/"
        ;;

     'generate-types' )
        # Use our custom SQL-based type generator which properly handles ltree and other types
        echo "Generating TypeScript types using SQL generator..."
        $WORKSPACE/devops/manage-statbus.sh psql < $WORKSPACE/devops/generate_database_types.sql
        echo "TypeScript types generated in app/src/lib/database.types.ts"
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
     * )
      echo "Unknown action '$action', select one of"
      awk -F "'" '/^ +''(..+)'' \)$/{print $2}' devops/manage-statbus.sh | sort
      exit 1
      ;;
esac
