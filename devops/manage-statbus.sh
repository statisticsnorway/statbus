#!/bin/bash
# devops/manage-statbus.sh
set -euo pipefail # Exit on error, unbound variable, or any failure in a pipeline

if test -n "${DEBUG:-}"; then
  set -x # Print all commands before running them - for easy debugging.
fi

WORKSPACE="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && cd .. && pwd )"
cd $WORKSPACE

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
        set_profile_arg "$@"

        # Always build the worker
        eval docker compose build worker

        # Conditionally add the --build argument if the profile is 'all' or 'all_except_app'
        # since docker compose does not use the --profile to determine
        # if a build is required.
        build_arg=""
        if [ "$profile" = "all" ] || [ "$profile" = "all_except_app" ]; then
            build_arg="--build"
        fi

        eval docker compose $compose_profile_arg up $build_arg --detach
      ;;
    'stop' )
        set_profile_arg "$@"
        eval docker compose $compose_profile_arg down
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
        ./devops/manage-statbus.sh test all > "$TEST_OUTPUT" 2>&1 || true

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
        
        # Check if no arguments were provided
        if [ ${#ORIGINAL_ARGS[@]} -eq 0 ]; then
            echo "Available tests:"
            echo "all"
            echo "failed"
            basename -s .sql "$PG_REGRESS_DIR/sql"/*.sql
            exit 0
        fi
        
        # Check for special keywords
        if [ "${ORIGINAL_ARGS[0]}" = "all" ]; then
            # Get all tests
            ALL_TESTS=$(basename -s .sql "$PG_REGRESS_DIR/sql"/*.sql)
            
            # Process exclusions (tests starting with -)
            TEST_BASENAMES=""
            for test in $ALL_TESTS; do
                exclude=false
                for arg in "${ORIGINAL_ARGS[@]:1}"; do  # Skip the first arg which is "all"
                    if [ "$arg" = "-$test" ]; then
                        exclude=true
                        break
                    fi
                done
                
                if [ "$exclude" = "false" ]; then
                    TEST_BASENAMES="$TEST_BASENAMES $test"
                fi
            done
        elif [ "${ORIGINAL_ARGS[0]}" = "failed" ]; then
            # Get failed tests
            FAILED_TESTS=$(grep -E '^not ok' $WORKSPACE/test/regression.out | sed -E 's/not ok[[:space:]]+[0-9]+[[:space:]]+- ([^[:space:]]+).*/\1/')
            
            # Process exclusions
            TEST_BASENAMES=""
            for test in $FAILED_TESTS; do
                exclude=false
                for arg in "${ORIGINAL_ARGS[@]:1}"; do  # Skip the first arg which is "failed"
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
            for arg in "${ORIGINAL_ARGS[@]}"; do
                if [[ "$arg" != -* ]]; then
                    TEST_BASENAMES="$TEST_BASENAMES $arg"
                fi
            done
        fi

        for test_basename in $TEST_BASENAMES; do
            expected_file="$PG_REGRESS_DIR/expected/$test_basename.out"
            if [ ! -f "$expected_file" ]; then
                echo "Warning: Expected output file $expected_file not found. Creating an empty placeholder."
                touch "$expected_file"
            fi
        done

        debug_arg=""
        if test -n "${DEBUG:-}"; then
          debug_arg="--debug"
        fi
        docker compose exec --workdir "/statbus" db \
            $PG_REGRESS $debug_arg \
            --use-existing \
            --bindir="/usr/lib/postgresql/$POSTGRESQL_MAJOR/bin" \
            --inputdir=$CONTAINER_REGRESS_DIR \
            --outputdir=$CONTAINER_REGRESS_DIR \
            --dbname=$PGDATABASE \
            --user=$PGUSER \
            $TEST_BASENAMES
    ;;
    'diff-fail-first' )
      if [ ! -f "$WORKSPACE/test/regression.out" ]; then
          echo "File $WORKSPACE/test/regression.out not found. Nothing to diff."
          exit 1
      fi

      # Extract the full test name from the regression output
      test_line=$(grep -E '^not ok' "$WORKSPACE/test/regression.out" | head -n 1)
      if [ -n "$test_line" ]; then
          # Extract the full test name (e.g., "01_load_web_examples")
          test=$(echo "$test_line" | sed -E 's/not ok[[:space:]]+[0-9]+[[:space:]]+- ([^[:space:]]+).*/\1/')
          
          ui=${1:-tui}
          shift || true
          case $ui in
              'gui')
                  echo "Running opendiff for test: $test"
                  opendiff $WORKSPACE/test/expected/$test.out $WORKSPACE/test/results/$test.out -merge $WORKSPACE/test/expected/$test.out
                  ;;
              'tui')
                  echo "Running vimdiff for test: $test"
                  vim -d $WORKSPACE/test/expected/$test.out $WORKSPACE/test/results/$test.out < /dev/tty
                  ;;
              *)
                  echo "Error: Unknown UI option '$ui'. Please use 'gui' or 'tui'."
                  exit 1
              ;;
          esac
      else
          echo "No failing tests found."
      fi
    ;;
    'diff-fail-all' )
      if [ ! -f "$WORKSPACE/test/regression.out" ]; then
          echo "File $WORKSPACE/test/regression.out not found. Nothing to diff."
          exit 1
      fi

      grep -E '^not ok' "$WORKSPACE/test/regression.out" | while read test_line; do
          # Extract the full test name (e.g., "01_load_web_examples")
          test=$(echo "$test_line" | sed -E 's/not ok[[:space:]]+[0-9]+[[:space:]]+- ([^[:space:]]+).*/\1/')
          echo "Next test: $test"
          echo "Press C to continue, s to skip, or b to break (default: C)"
          read -n 1 -s input < /dev/tty
          if [ "$input" = "b" ]; then
              break
          elif [ "$input" = "s" ]; then
              continue
          fi
          case "${2:-}" in
              'ui')
                  echo "Running opendiff for test: $test"
                  opendiff $WORKSPACE/test/expected/$test.out $WORKSPACE/test/results/$test.out -merge $WORKSPACE/test/expected/$test.out
                  ;;
              'text'|*)
                  echo "Running vimdiff for test: $test"
                  vim -d $WORKSPACE/test/expected/$test.out $WORKSPACE/test/results/$test.out < /dev/tty
                  ;;
          esac
      done
    ;;
    'make-all-failed-test-results-expected' )
        if [ ! -f "$WORKSPACE/test/regression.out" ]; then
            echo "No regression.out file found. Run tests first to generate failures."
            exit 1
        fi

        grep -E '^not ok' "$WORKSPACE/test/regression.out" | while read -r test_line; do
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
    'activate_sql_saga' )
        PGUSER=supabase_admin ./devops/manage-statbus.sh psql -c 'create extension sql_saga cascade;'
      ;;
    'build-statbus-cli' )
        pushd cli
          shards build
        popd
      ;;
    'create-db-structure' )
        pushd cli
          shards build statbus && ./bin/statbus migrate up all -v
        popd
      ;;
    'delete-db-structure' )
        pushd cli
          shards build statbus&& ./bin/statbus migrate down all -v
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
        JWT_SECRET=$(./devops/dotenv --file .env.credentials get JWT_SECRET)
        DEPLOYMENT_SLOT_CODE=$(./devops/dotenv --file .env.config get DEPLOYMENT_SLOT_CODE)
        PGDATABASE=statbus_${DEPLOYMENT_SLOT_CODE:-dev}
        ./devops/manage-statbus.sh psql -c "ALTER DATABASE $PGDATABASE SET app.settings.jwt_secret TO '$JWT_SECRET';"
        ./devops/manage-statbus.sh psql -c "ALTER DATABASE $PGDATABASE SET app.settings.deployment_slot_code TO '$DEPLOYMENT_SLOT_CODE';"
        ./devops/manage-statbus.sh psql -c "SELECT pg_reload_conf();"
        ./devops/manage-statbus.sh create-db-structure
        ./devops/manage-statbus.sh create-users
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
     'generate-config' )
        ./cli/bin/statbus manage generate-config
        ;;
     'postgres-variables' )
        PGHOST=127.0.0.1
        PGPORT=$(./devops/dotenv --file .env get DB_PUBLIC_LOCALHOST_PORT)
        PGDATABASE=$(./devops/dotenv --file .env get POSTGRES_APP_DB)
        # Preserve the USER if already setup, to allow overrides.
        PGUSER=${PGUSER:-$(./devops/dotenv --file .env get POSTGRES_ADMIN_USER)}
        PGPASSWORD=$(./devops/dotenv --file .env get POSTGRES_ADMIN_PASSWORD)
        cat <<EOS
export PGHOST=$PGHOST PGPORT=$PGPORT PGDATABASE=$PGDATABASE PGUSER=$PGUSER PGPASSWORD=$PGPASSWORD
EOS
      ;;
     'psql' )
        eval $(./devops/manage-statbus.sh postgres-variables)
        # The local psql is always tried first, as it has access to files
        # used for copying in data.
        if $(which psql > /dev/null); then
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
        tables=$(./devops/manage-statbus.sh psql -t -c "
          (SELECT schemaname || '.' || tablename
           FROM pg_catalog.pg_tables
           WHERE schemaname IN ('admin', 'db', 'lifecycle_callbacks', 'public', 'auth'))
          UNION ALL
          (SELECT schemaname || '.' || matviewname
           FROM pg_catalog.pg_matviews
           WHERE schemaname IN ('admin', 'db', 'lifecycle_callbacks', 'public', 'auth'))
          ORDER BY 1;")

        views=$(./devops/manage-statbus.sh psql -t -c "
          SELECT schemaname || '.' || viewname
          FROM pg_catalog.pg_views
          WHERE schemaname IN ('admin', 'db', 'lifecycle_callbacks', 'public', 'auth')
          ORDER BY 1;")

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
        functions=$(./devops/manage-statbus.sh psql -t -c "
          SELECT n.nspname || '.' || p.proname || '(' ||
            regexp_replace(
              regexp_replace(
                regexp_replace(
                  pg_get_function_arguments(p.oid),
                  'timestamp with time zone',
                  'timestamptz',
                  'g'
                ),
                ',?\s*OUT [^,\$]+|\s*DEFAULT [^,\$]+|IN (\w+\s+)|INOUT (\w+\s+)',
                '\1',
                'g'
              ),
              '\w+\s+(\w+)',
              '\1',
              'g'
            ) || ')'
          FROM pg_proc p
          JOIN pg_namespace n ON p.pronamespace = n.oid
          WHERE n.nspname IN ('admin', 'db', 'lifecycle_callbacks', 'public', 'auth')
          AND p.prokind != 'a'  -- Exclude aggregate functions
          AND NOT (
              (n.nspname = 'public' AND p.proname LIKE '\_%') OR
              (n.nspname = 'public' AND p.proname LIKE 'index') OR
              (n.nspname = 'public' AND p.proname LIKE 'lca') OR
              (n.nspname = 'public' AND p.proname LIKE 'lquery\_%') OR
              (n.nspname = 'public' AND p.proname LIKE 'lt\_%') OR
              (n.nspname = 'public' AND p.proname LIKE 'ltq\_%') OR
              (n.nspname = 'public' AND p.proname LIKE 'ltxtq\_%') OR
              (n.nspname = 'public' AND p.proname LIKE 'nlevel') OR
              (n.nspname = 'public' AND p.proname LIKE 'subltree') OR
              (n.nspname = 'public' AND p.proname LIKE 'subpath') OR
              (n.nspname = 'public' AND p.proname LIKE 'text2ltree') OR
              (n.nspname = 'public' AND p.proname LIKE 'gbtree%') OR
              (n.nspname = 'public' AND p.proname LIKE 'ltree%') OR
              (n.nspname = 'public' AND p.proname LIKE '%\_dist') OR
              (n.nspname = 'public' AND p.proname LIKE 'gbt\_%') OR
              (n.nspname = 'public' AND p.proname = 'decode_error_level') OR
              (n.nspname = 'public' AND p.proname LIKE 'decrypt%') OR
              (n.nspname = 'public' AND p.proname LIKE 'digest%') OR
              (n.nspname = 'public' AND p.proname LIKE 'encrypt%') OR
              (n.nspname = 'public' AND p.proname LIKE 'gen\_random\_%') OR
              (n.nspname = 'public' AND p.proname LIKE 'gen\_salt%') OR
              (n.nspname = 'public' AND p.proname LIKE 'get\_%') OR
              (n.nspname = 'public' AND p.proname LIKE 'gin\_%\_trgm%') OR
              (n.nspname = 'public' AND p.proname LIKE 'gtrgm\_%') OR
              (n.nspname = 'public' AND p.proname LIKE 'hash\_%') OR
              (n.nspname = 'public' AND p.proname = 'histogram') OR
              (n.nspname = 'public' AND p.proname LIKE 'hmac%') OR
              (n.nspname = 'public' AND p.proname LIKE 'http%') OR
              (n.nspname = 'public' AND p.proname = 'dearmor') OR
              (n.nspname = 'public' AND p.proname LIKE 'hypopg%') OR
              (n.nspname = 'public' AND p.proname LIKE 'id\_decode%') OR
              (n.nspname = 'public' AND p.proname LIKE 'id\_encode%') OR
              (n.nspname = 'public' AND p.proname = 'index_advisor') OR
              (n.nspname = 'public' AND p.proname LIKE 'pg\_stat\_monitor%') OR
              (n.nspname = 'public' AND p.proname LIKE 'pg\_stat\_statements%') OR
              (n.nspname = 'public' AND p.proname LIKE 'pgp\_%') OR
              (n.nspname = 'public' AND p.proname LIKE 'pgsm\_%') OR
              (n.nspname = 'public' AND p.proname LIKE 'plpgsql\_check%') OR
              (n.nspname = 'public' AND p.proname LIKE 'plpgsql\_coverage%') OR
              (n.nspname = 'public' AND p.proname LIKE 'plpgsql\_profiler%') OR
              (n.nspname = 'public' AND p.proname LIKE 'plpgsql\_show%') OR
              (n.nspname = 'public' AND p.proname = 'range') OR
              (n.nspname = 'public' AND p.proname LIKE 'set\_limit%') OR
              (n.nspname = 'public' AND p.proname LIKE 'show\_%') OR
              (n.nspname = 'public' AND p.proname = 'sign') OR
              (n.nspname = 'public' AND p.proname LIKE 'similarity%') OR
              (n.nspname = 'public' AND p.proname LIKE 'strict\_word\_similarity%') OR
              (n.nspname = 'public' AND p.proname = 'text_to_bytea') OR
              (n.nspname = 'public' AND p.proname LIKE 'tri\_fkey%') OR
              (n.nspname = 'public' AND p.proname = 'try_cast_double') OR
              (n.nspname = 'public' AND p.proname LIKE 'url\_%') OR
              (n.nspname = 'public' AND p.proname LIKE 'urlencode%') OR
              (n.nspname = 'public' AND p.proname = 'verify') OR
              (n.nspname = 'public' AND p.proname LIKE 'word\_similarity%')
          )
          ORDER BY 1;")

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
        pushd $WORKSPACE/app
        # Activate the Node.js version from .nvmrc using fnm
        eval "$(fnm env --use-on-cd)" || { echo "Failed to set up fnm environment"; exit 1; }
        fnm use || { echo "Failed to activate Node version from .nvmrc"; exit 1; }
        
        # Get database connection details
        eval $($WORKSPACE/devops/manage-statbus.sh postgres-variables) || { echo "Failed to get database variables"; exit 1; }
        db_url="postgresql://$PGUSER:$PGPASSWORD@$PGHOST:$PGPORT/$PGDATABASE?sslmode=disable"
        
        # First run: This will prompt for package installation if needed
        # When running for the first time, npx will ask for confirmation to install the package
        # This interactive step cannot be redirected to a file
        echo "Running initial command to handle any package installation prompts..."
        npx supabase@beta gen types typescript --db-url "$db_url" || { echo "Failed to run supabase gen types"; exit 1; }
        
        # Second run: Now that the package is installed, we can redirect the output
        # This run will not prompt for confirmation since the package is already installed
        echo "Generating TypeScript types file..."
        npx supabase@beta gen types typescript --db-url "$db_url" > src/lib/database.types.ts
      ;;
     * )
      echo "Unknown action '$action', select one of"
      awk -F "'" '/^ +''(..+)'' \)$/{print $2}' devops/manage-statbus.sh
      exit 1
      ;;
esac
