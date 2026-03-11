#!/bin/bash
# devops/manage-statbus.sh — Backward-compatibility wrapper
#
# DEPRECATED: This file will be deleted once all references are migrated.
#
# Delegates to ./sb (Go CLI) when available, ./dev.sh for dev commands.
# Falls back to direct implementations when ./sb is not built yet
# (e.g., on cloud servers before the upgrade system is deployed).
#
# New code should call ./sb or ./dev.sh directly.
# References to update: deploy.sh, CI workflows, documentation, SSH aliases.
#
set -euo pipefail

if [ "${DEBUG:-}" = "true" ] || [ "${DEBUG:-}" = "1" ]; then
  set -x
fi

# Ensure Homebrew environment is set up for tools like 'shards'
if test -f /etc/profile.d/homebrew.sh; then
  source /etc/profile.d/homebrew.sh
fi

WORKSPACE="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && cd .. && pwd )"
cd "$WORKSPACE"

# Set TTY_INPUT to /dev/tty if available (interactive), otherwise /dev/null
if [ -e /dev/tty ]; then
  export TTY_INPUT=/dev/tty
else
  export TTY_INPUT=/dev/null
fi

# Check if the Go binary is available
has_sb() {
    [ -x "$WORKSPACE/sb" ]
}

# Check if dev.sh is available
has_devsh() {
    [ -x "$WORKSPACE/dev.sh" ]
}

action=${1:-}
shift || true

# --- Helper: postgres-variables (needed by fallback psql) ---
_postgres_variables() {
    if has_sb; then
        SITE_DOMAIN=$(./sb dotenv -f .env get SITE_DOMAIN || echo "local.statbus.org")
        PGDATABASE=$(./sb dotenv -f .env get POSTGRES_APP_DB)
        PGUSER=${PGUSER:-$(./sb dotenv -f .env get POSTGRES_ADMIN_USER)}
        PGPASSWORD=$(./sb dotenv -f .env get POSTGRES_ADMIN_PASSWORD)
        PGPORT=$(./sb dotenv -f .env get CADDY_DB_PORT)
    elif [ -x "$WORKSPACE/devops/dotenv" ]; then
        SITE_DOMAIN=$(./devops/dotenv --file .env get SITE_DOMAIN || echo "local.statbus.org")
        PGDATABASE=$(./devops/dotenv --file .env get POSTGRES_APP_DB)
        PGUSER=${PGUSER:-$(./devops/dotenv --file .env get POSTGRES_ADMIN_USER)}
        PGPASSWORD=$(./devops/dotenv --file .env get POSTGRES_ADMIN_PASSWORD)
        PGPORT=$(./devops/dotenv --file .env get CADDY_DB_PORT)
    else
        echo "Error: Neither ./sb nor ./devops/dotenv available" >&2
        exit 1
    fi
    PGHOST=$SITE_DOMAIN
    PGSSLMODE=disable
    export PGHOST PGPORT PGDATABASE PGUSER PGPASSWORD PGSSLMODE
}

# --- Helper: set_profile_arg (needed by fallback start/stop) ---
set_profile_arg() {
    profile=${1:-}
    available_profiles=$(docker compose config --profiles)
    if test -z "$profile"; then
        echo "No profile provided. Available profiles are:"
        echo "$available_profiles"
        exit 1
    fi
    if ! echo "$available_profiles" | grep -wq "$profile"; then
        echo "Error: Profile '$profile' does not exist in docker compose."
        exit 1
    fi
    compose_profile_arg="--profile \"$profile\""
    shift || true
}

case "$action" in
    # === Commands with Go delegation + fallback ===

    'start' )
        if has_sb; then
            exec ./sb start "$@"
        fi
        VERSION=$(git describe --always)
        if has_sb; then
            ./sb dotenv -f .env set VERSION=$VERSION
        else
            ./devops/dotenv --file .env set VERSION=$VERSION
        fi
        $0 build-statbus-cli
        $0 generate-config
        target_service_or_profile="${1:-}"
        if [ "$target_service_or_profile" = "app" ]; then
            docker compose up --build --detach app
        else
            set_profile_arg "$@"
            eval docker compose $compose_profile_arg up --build --detach
        fi
      ;;
    'stop' )
        if has_sb; then
            exec ./sb stop "$@"
        fi
        target_service_or_profile="${1:-}"
        if [ "$target_service_or_profile" = "app" ]; then
            docker compose down --remove-orphans app
        else
            set_profile_arg "$@"
            eval docker compose $compose_profile_arg down --remove-orphans
        fi
      ;;
    'restart' )
        if has_sb; then
            exec ./sb restart "$@"
        fi
        $0 stop "$@"
        $0 start "$@"
      ;;
    'logs' )
        if has_sb; then exec ./sb logs "$@"; fi
        eval docker compose logs --follow
      ;;
    'ps' )
        if has_sb; then exec ./sb ps "$@"; fi
        eval docker compose ps
      ;;
    'build' )
        if has_sb; then exec ./sb build "$@"; fi
        docker compose build
      ;;
    'psql' )
        if has_sb; then
            exec ./sb psql "$@"
        fi
        _postgres_variables
        if [ -z "${DOCKER_PSQL:-}" ] && $(which psql > /dev/null); then
          psql "$@"
        else
          if test -t 0 && test -t 1 && test ! -p /dev/stdin && test ! -f /dev/stdin; then
            docker compose exec -w /statbus -e PGPASSWORD -u postgres db psql -U $PGUSER $PGDATABASE "$@"
          else
            docker compose exec -T -w /statbus -e PGPASSWORD -u postgres db psql -U $PGUSER $PGDATABASE "$@"
          fi
        fi
      ;;
    'generate-config' )
        if has_sb; then
            exec ./sb config generate "$@"
        fi
        # Fallback: use Crystal CLI
        if [ ! -f .env ]; then
            slot_offset=1
            if [ -t 0 ]; then
                read -p "Enter deployment slot port offset [1]: " user_slot_offset
                slot_offset=${user_slot_offset:-1}
            fi
            ./devops/dotenv --file .env.config set DEPLOYMENT_SLOT_PORT_OFFSET "${slot_offset}"
            base_port=3000; slot_multiplier=10
            port_offset=$((base_port + slot_offset * slot_multiplier))
            db_port=$((port_offset + 4))
            export CADDY_DB_PORT=$db_port
        fi
        ./cli/bin/statbus manage generate-config
      ;;
    'create-users' )
        if has_sb; then exec ./sb users create "$@"; fi
        ./cli/bin/statbus manage create-users -v
      ;;

    # === Database commands ===
    'dump-db' )
        if has_sb; then exec ./sb db dump "$@"; fi
        echo "Error: ./sb not available. Build with: cd cli && make build" >&2
        exit 1
      ;;
    'download-db' )
        if has_sb; then exec ./sb db download "$@"; fi
        echo "Error: ./sb not available. Build with: cd cli && make build" >&2
        exit 1
      ;;
    'list-db-dumps' )
        if has_sb; then exec ./sb db dumps list "$@"; fi
        ls -lh "$WORKSPACE/dbdumps/"*.pg_dump 2>/dev/null || echo "  (none)"
      ;;
    'purge-db-dumps' )
        if has_sb; then exec ./sb db dumps purge "$@"; fi
        echo "Error: ./sb not available. Build with: cd cli && make build" >&2
        exit 1
      ;;
    'restore-db' )
        if has_sb; then exec ./sb db restore "$@"; fi
        echo "Error: ./sb not available. Build with: cd cli && make build" >&2
        exit 1
      ;;
    'is-db-running' )
        if has_sb; then exec ./sb db status "$@"; fi
        docker compose exec -T db pg_isready -U postgres > /dev/null 2>&1
      ;;

    # === Type generation ===
    'generate-types' )
        if has_sb; then exec ./sb types generate "$@"; fi
        # Fallback: direct psql
        _postgres_variables
        psql < "$WORKSPACE/devops/generate_database_types.sql"
      ;;

    # === Development commands (delegate to dev.sh when available) ===
    'test' )
        if has_devsh; then exec ./dev.sh test "$@"; fi
        echo "Error: ./dev.sh not found" >&2; exit 1
      ;;
    'test-isolated' )
        if has_devsh; then exec ./dev.sh test-isolated "$@"; fi
        echo "Error: ./dev.sh not found" >&2; exit 1
      ;;
    'continous-integration-test' )
        if has_devsh; then exec ./dev.sh continous-integration-test "$@"; fi
        echo "Error: ./dev.sh not found" >&2; exit 1
      ;;
    'diff-fail-first' )
        if has_devsh; then exec ./dev.sh diff-fail-first "$@"; fi
        echo "Error: ./dev.sh not found" >&2; exit 1
      ;;
    'diff-fail-all' )
        if has_devsh; then exec ./dev.sh diff-fail-all "$@"; fi
        echo "Error: ./dev.sh not found" >&2; exit 1
      ;;
    'make-all-failed-test-results-expected' )
        if has_devsh; then exec ./dev.sh make-all-failed-test-results-expected "$@"; fi
        echo "Error: ./dev.sh not found" >&2; exit 1
      ;;
    'create-test-template' )
        if has_devsh; then exec ./dev.sh create-test-template "$@"; fi
        echo "Error: ./dev.sh not found" >&2; exit 1
      ;;
    'clean-test-databases' )
        if has_devsh; then exec ./dev.sh clean-test-databases "$@"; fi
        echo "Error: ./dev.sh not found" >&2; exit 1
      ;;

    # === DB lifecycle (with fallback for deploy.sh compatibility) ===
    'create-db' )
        if has_devsh && has_sb; then exec ./dev.sh create-db "$@"; fi
        $0 start all_except_app
        $0 create-db-structure
        $0 create-users
        $0 create-test-template 2>/dev/null || true
      ;;
    'delete-db' )
        if has_devsh && has_sb; then exec ./dev.sh delete-db "$@"; fi
        $0 stop all
        POSTGRES_DIRECTORY="$WORKSPACE/postgres/volumes/db/data"
        if [ -d "$POSTGRES_DIRECTORY" ]; then
          if ! test -r "$POSTGRES_DIRECTORY" || ! test -w "$POSTGRES_DIRECTORY" || ! test -x "$POSTGRES_DIRECTORY"; then
            sudo rm -rf "$POSTGRES_DIRECTORY"
          else
            rm -rf "$POSTGRES_DIRECTORY"
          fi
        fi
      ;;
    'recreate-database' )
        if has_devsh && has_sb; then exec ./dev.sh recreate-database "$@"; fi
        $0 delete-db
        $0 create-db
      ;;
    'create-db-structure' )
        if has_devsh && has_sb; then exec ./dev.sh create-db-structure "$@"; fi
        # Fallback: use Crystal CLI for migrations
        _postgres_variables
        SNAPSHOT_DIR="$WORKSPACE/migrations/snapshots"
        LATEST_SNAPSHOT=$(find "$SNAPSHOT_DIR" -maxdepth 1 -name 'schema_*.pg_dump' -type f 2>/dev/null | sort -V | tail -1 || true)
        if [ -n "$LATEST_SNAPSHOT" ]; then
            SNAPSHOT_VERSION=$(basename "$LATEST_SNAPSHOT" | sed 's/schema_\([0-9]*\)\.pg_dump/\1/')
            SNAPSHOT_LIST="${LATEST_SNAPSHOT%.pg_dump}.pg_list"
            echo "Restoring from snapshot: $LATEST_SNAPSHOT"
            RESTORE_EXIT_CODE=0
            if [ -f "$SNAPSHOT_LIST" ]; then
                docker compose cp "$SNAPSHOT_LIST" db:/tmp/restore.pg_list
                docker compose exec -T db pg_restore -U postgres --clean --if-exists --no-owner --disable-triggers --single-transaction -L /tmp/restore.pg_list -d "$PGDATABASE" < "$LATEST_SNAPSHOT" || RESTORE_EXIT_CODE=$?
                docker compose exec -T db rm -f /tmp/restore.pg_list
            else
                docker compose exec -T db pg_restore -U postgres --clean --if-exists --no-owner --disable-triggers --single-transaction -d "$PGDATABASE" < "$LATEST_SNAPSHOT" || RESTORE_EXIT_CODE=$?
            fi
            if [ $RESTORE_EXIT_CODE -gt 1 ]; then
                echo "Error: pg_restore failed with exit code $RESTORE_EXIT_CODE"
                exit 1
            fi
        fi
        if has_sb; then
            ./sb migrate up
        else
            ./cli/bin/statbus migrate up all -v
        fi
        # Load secrets
        if has_sb; then
            JWT_SECRET=$(./sb dotenv -f .env.credentials get JWT_SECRET)
            DEPLOYMENT_SLOT_CODE=$(./sb dotenv -f .env.config get DEPLOYMENT_SLOT_CODE)
        else
            JWT_SECRET=$(./devops/dotenv --file .env.credentials get JWT_SECRET)
            DEPLOYMENT_SLOT_CODE=$(./devops/dotenv --file .env.config get DEPLOYMENT_SLOT_CODE)
        fi
        PGDATABASE=statbus_${DEPLOYMENT_SLOT_CODE:-dev}
        $0 psql -c "INSERT INTO auth.secrets (key, value, description) VALUES ('jwt_secret', '$JWT_SECRET', 'JWT signing secret') ON CONFLICT (key) DO UPDATE SET value = EXCLUDED.value, updated_at = clock_timestamp();"
        $0 psql -c "ALTER DATABASE $PGDATABASE SET app.settings.deployment_slot_code TO '$DEPLOYMENT_SLOT_CODE';"
      ;;
    'delete-db-structure' )
        if has_devsh && has_sb; then exec ./dev.sh delete-db-structure "$@"; fi
        if has_sb; then
            ./sb migrate down all
        else
            pushd cli; shards build statbus && ./bin/statbus migrate down all -v; popd
        fi
      ;;
    'reset-db-structure' )
        if has_devsh && has_sb; then exec ./dev.sh reset-db-structure "$@"; fi
        $0 delete-db-structure
        $0 create-db-structure
        $0 create-users
      ;;
    'dump-snapshot' )
        if has_devsh; then exec ./dev.sh dump-snapshot "$@"; fi
        echo "Error: ./dev.sh not found" >&2; exit 1
      ;;
    'list-snapshots' )
        if has_devsh; then exec ./dev.sh list-snapshots "$@"; fi
        echo "Error: ./dev.sh not found" >&2; exit 1
      ;;
    'generate-db-documentation' )
        if has_devsh; then exec ./dev.sh generate-db-documentation "$@"; fi
        echo "Error: ./dev.sh not found" >&2; exit 1
      ;;
    'postgres-variables' )
        if has_devsh; then exec ./dev.sh postgres-variables "$@"; fi
        # Inline fallback for deploy.sh compatibility
        _postgres_variables
        echo "export PGHOST=$PGHOST PGPORT=$PGPORT PGDATABASE=$PGDATABASE PGUSER=$PGUSER PGPASSWORD=$PGPASSWORD PGSSLMODE=$PGSSLMODE"
      ;;
    'compile-run-and-trace-dev-app-in-container' )
        if has_devsh; then exec ./dev.sh compile-run-and-trace-dev-app-in-container "$@"; fi
        echo "Error: ./dev.sh not found" >&2; exit 1
      ;;

    # === Legacy Crystal commands ===
    'build-statbus-cli' )
        if has_sb; then
            echo "Note: Crystal CLI build is no longer needed (Go binary ./sb replaces it)."
            return 0 2>/dev/null || exit 0
        fi
        pushd cli; shards build; popd
      ;;

    * )
      echo "manage-statbus.sh — Backward-compatibility wrapper"
      echo ""
      echo "This script delegates to ./sb (ops) and ./dev.sh (development)."
      echo "Consider calling them directly:"
      echo ""
      echo "  ./sb <command>    — Production/ops commands"
      echo "  ./dev.sh <command> — Development commands"
      echo ""
      echo "Run './sb --help' or './dev.sh' for available commands."
      if [ -n "$action" ]; then
          echo ""
          echo "Error: Unknown command '$action'"
          exit 1
      fi
      ;;
esac
