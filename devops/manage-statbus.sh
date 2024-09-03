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
    profile=${1:-all}
    compose_profile_arg="--profile \"$profile\""
    shift || true
}

case "$action" in
    'start' )
        VERSION=$(git describe --always)
        ./devops/dotenv --file .env set VERSION=$VERSION
        set_profile_arg "$@"

        # Conditionally add the --build argument if the profile is 'all'
        # since docker compose does not use the --profile to determine
        # if a build is required.
        build_arg=""
        if [ "$profile" = "all" ]; then
            build_arg="--build"
        fi

        eval docker compose $compose_profile_arg up $build_arg --detach
      ;;
    'stop' )
        set_profile_arg "$@"
        eval docker compose $compose_profile_arg down
      ;;
    'logs' )
        set_profile_arg "$@"
        eval docker compose $compose_profile_arg logs --follow
      ;;
    'ps' )
        set_profile_arg "$@"
        eval docker compose $compose_profile_arg ps
      ;;
    'test' )
        eval $(./devops/manage-statbus.sh postgres-variables)

        PG_REGRESS_DIR="$WORKSPACE/test"
        PG_REGRESS="/usr/lib/postgresql/15/lib/pgxs/src/test/regress/pg_regress"
        CONTAINER_REGRESS_DIR="/statbus/test"

        for suffix in "sql" "expected" "results"; do
            if ! test -d "$PG_REGRESS_DIR/$suffix"; then
                mkdir -p "$PG_REGRESS_DIR/$suffix"
            fi
        done

        TEST_BASENAMES="$@"
        if test -z "$TEST_BASENAMES"; then
            echo "Available tests:"
            basename -s .sql "$PG_REGRESS_DIR/sql"/*.sql
            exit 0
        elif test "$TEST_BASENAMES" = "all"; then
            TEST_BASENAMES=$(basename -s .sql "$PG_REGRESS_DIR/sql"/*.sql)
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
            --bindir='/usr/lib/postgresql/15/bin' \
            --inputdir=$CONTAINER_REGRESS_DIR \
            --outputdir=$CONTAINER_REGRESS_DIR \
            --dbname=$PGDATABASE \
            --user=$PGUSER \
            $TEST_BASENAMES
    ;;
    'activate_sql_saga' )
        eval $(./devops/manage-statbus.sh postgres-variables)
        PGUSER=supabase_admin psql -c 'create extension sql_saga cascade;'
      ;;
    'create-db-structure' )
        ./devops/manage-statbus.sh psql < dbseed/create-db-structure.sql 2>&1
      ;;
    'delete-db-structure' )
        ./devops/manage-statbus.sh psql < dbseed/delete-db-structure.sql 2>&1
      ;;
    'reset-db-structure' )
        ./devops/manage-statbus.sh delete-db-structure
        ./devops/manage-statbus.sh create-db-structure
        ./devops/manage-statbus.sh create-users
      ;;
    'recreate-database' )
        ./devops/recreate-database.sh
      ;;
    'delete-db' )
        # Define the directory path
        DIRECTORY="$WORKSPACE/supabase_docker/volumes/db/data"

        # Check if the directory is accessible
        if ! test -r "$DIRECTORY" || ! test -w "$DIRECTORY" || ! test -x "$DIRECTORY"; then
          echo "Removing with sudo"
          sudo rm -rf "$DIRECTORY"
        else
          rm -rf "$DIRECTORY"
        fi
      ;;
    'create-users' )
        export $(awk -F= '/^[^#]/{output=output" "$1"="$2} END {print output}' .env)
        echo "Wait for admin api (gotrue) to start"
        starting=true
        while $starting; do
            sleep 1
            curl "http://$SUPABASE_BIND_ADDRESS/auth/v1/health" \
            -H 'accept: application/json' \
            -H "apikey: $SERVICE_ROLE_KEY" && starting=false
        done

        echo Create users for the developers
        echo 'Creating users defined in .users.yml'

        # Read from the YAML file directly and iterate over each object
        yq -r '.[] | "\(.email) \(.password)"' .users.yml | while read -r user_details; do
          # Extract user details from the formatted output
          email=$(echo "${user_details}" | awk '{print $1}')
          password=$(echo "${user_details}" | awk '{print $2}')

          # Use the official API, since there isn't an SQL route for this! :-(
          # Run the curl command for each user
          curl "http://$SUPABASE_BIND_ADDRESS/auth/v1/admin/users" \
            -H 'accept: application/json' \
            -H "apikey: $SERVICE_ROLE_KEY" \
            -H "authorization: Bearer $SERVICE_ROLE_KEY" \
            -H 'content-type: application/json' \
            --data-raw "{\"email\":\"$email\", \"password\":\"$password\", \"email_confirm\":true}"
          ./devops/manage-statbus.sh psql <<EOS
            INSERT INTO public.statbus_user (uuid, role_id)
            SELECT id, (SELECT id FROM public.statbus_role WHERE type = 'super_user')
            FROM auth.users
            WHERE email like '$email'
            ON CONFLICT (uuid)
            DO UPDATE SET role_id = EXCLUDED.role_id;
EOS
        done
      ;;
     'upgrade_supabase' )
        git reset supabase_docker
        if test ! -d ../supabase; then
            pushd ..
            git clone https://github.com/supabase/supabase
            popd
        fi
        pushd ../supabase
        git pull
        rsync -av docker/ ../statbus/supabase_docker
        popd
        git add supabase_docker
        ./devops/manage-statbus.sh generate-docker-compose-adjustments
        git add docker-compose.supabase_docker.*
        git commit -m 'Upgraded Supabase Docker'
      ;;
     'generate-config' )
        if ! test -f .users.yml; then
            echo "Copy .users.example to .users.yml and add your admin users"
            exit 1
        fi

        CREDENTIALS_FILE=".env.credentials"
        echo Using credentials from $CREDENTIALS_FILE
        POSTGRES_PASSWORD=$(./devops/dotenv --file $CREDENTIALS_FILE generate POSTGRES_PASSWORD pwgen 20)
        JWT_SECRET=$(./devops/dotenv --file $CREDENTIALS_FILE generate JWT_SECRET pwgen 32)
        DASHBOARD_USERNAME=$(./devops/dotenv --file $CREDENTIALS_FILE generate DASHBOARD_USERNAME echo admin)
        DASHBOARD_PASSWORD=$(./devops/dotenv --file $CREDENTIALS_FILE generate DASHBOARD_PASSWORD pwgen 20)

        CONFIG_FILE=".env.config"
        echo Using config from $CONFIG_FILE
        # The name displayed on the web
        DEPLOYMENT_SLOT_NAME=$(./devops/dotenv --file $CONFIG_FILE generate DEPLOYMENT_SLOT_NAME echo "Development")
        # Unique code used on the server for distinct docker namespaces
        DEPLOYMENT_SLOT_CODE=$(./devops/dotenv --file $CONFIG_FILE generate DEPLOYMENT_SLOT_CODE echo "dev")
        # Offset to calculate ports exposed by docker compose
        DEPLOYMENT_SLOT_PORT_OFFSET=$(./devops/dotenv --file $CONFIG_FILE generate DEPLOYMENT_SLOT_PORT_OFFSET echo "1")
        # Urls configured in Caddy and DNS.
        STATBUS_URL=$(./devops/dotenv --file $CONFIG_FILE generate STATBUS_URL echo "http://localhost:3010")
        SUPABASE_URL=$(./devops/dotenv --file $CONFIG_FILE generate SUPABASE_URL echo "http://localhost:3011")
        # Logging server
        SEQ_SERVER_URL=$(./devops/dotenv --file $CONFIG_FILE generate SEQ_SERVER_URL echo "https://log.statbus.org")
        SEQ_API_KEY=$(./devops/dotenv --file $CONFIG_FILE generate SEQ_API_KEY echo "secret_seq_api_key")
        SLACK_TOKEN=$(./devops/dotenv --file $CONFIG_FILE generate SLACK_TOKEN echo "secret_slack_api_token")

        # Prepare a new environment file
        # Check if the original file exists
        if test -f .env; then
            # Use the current date as the base for the backup suffix
            backup_base=$(date -u +%Y-%m-%d)
            backup_suffix="backup.$backup_base"
            counter=1

            # Loop to find a unique backup file name
            while test -f ".env.$backup_suffix"; do
                # If a file with the current suffix exists, increment the counter and append it to the suffix
                backup_suffix="backup.${backup_base}_$counter"
                ((counter++))
            done

            # Inform the user about the replacement and backup process
            echo "Replacing .env - the old version is backed up as .env.$backup_suffix"

            # Move the original file to its backup location with the unique suffix
            mv .env ".env.$backup_suffix"
        fi

        cat > .env <<'EOS'
################################################################
# Statbus Environment Variables
# Generated by `./devops/manage-statbus.sh generate-config`
# Used by docker compose, both for statbus containers
# and for the included supabase containers.
# The files:
#   `.env.credentials` generated if missing, with stable credentials.
#   `.env.config` generated if missing, configuration for installation.
#   `.env` generated with input from `.env.credentials` and `.env.config`
# The `.env` file contains settings used both by
# the statbus app (Backend/frontend) and by the Supabase Docker
# containers.
# The top level `docker-compose.yml` file includes all configuration
# required for all statbus docker containers, but must be managed
# by `./devops/manage-statbus.sh` that also sets the VERSION
# required for precise logging by the statbus app.
################################################################

EOS

        cat >> .env <<'EOS'

################################################################
# Statbus Container Configuration
################################################################

# The name displayed on the web
DEPLOYMENT_SLOT_NAME=Example
# Urls configured in Caddy and DNS.
STATBUS_URL=https://www.ex.statbus.org
SUPABASE_URL=https://api.ex.statbus.org
# Logging server
SEQ_SERVER_URL=https://log.statbus.org
SEQ_API_KEY=secret_seq_api_key
# Deployment Messages
SLACK_TOKEN=secret_slack_api_token
# The prefix used for all container names in docker
COMPOSE_INSTANCE_NAME=statbus
# The host address connected to the STATBUS app
APP_BIND_ADDRESS=127.0.0.1:3010
# The host address connected to Supabase
SUPABASE_BIND_ADDRESS=127.0.0.1:3011
# The publicly exposed address of PostgreSQL inside Supabase
DB_PUBLIC_LOCALHOST_PORT=3432
# Updated by manage-statbus.sh start
VERSION=commit_sha_or_version_of_deployed_commit
EOS

        cat >> .env <<'EOS'

################################################################
## Supabase Container Configuation
# Adapted from supabase_docker/.env.example
################################################################


EOS
        cat supabase_docker/.env.example >> .env

        echo "Setting Statbus Container Configuration"
        ./devops/dotenv --file .env set DEPLOYMENT_SLOT_NAME="$DEPLOYMENT_SLOT_NAME"
        ./devops/dotenv --file .env set COMPOSE_INSTANCE_NAME="statbus-$DEPLOYMENT_SLOT_CODE"
        ./devops/dotenv --file .env set STATBUS_URL=$STATBUS_URL
        ./devops/dotenv --file .env set SUPABASE_URL=$SUPABASE_URL
        ./devops/dotenv --file .env set SEQ_SERVER_URL=$SEQ_SERVER_URL
        ./devops/dotenv --file .env set SEQ_API_KEY=$SEQ_API_KEY

        APP_BIND_ADDRESS="127.0.0.1:$(( 3000+$DEPLOYMENT_SLOT_PORT_OFFSET*10 ))"
        ./devops/dotenv --file .env set APP_BIND_ADDRESS=$APP_BIND_ADDRESS

        SUPABASE_BIND_ADDRESS="127.0.0.1:$(( 3000+$DEPLOYMENT_SLOT_PORT_OFFSET*10+1 ))"
        ./devops/dotenv --file .env set SUPABASE_BIND_ADDRESS=$SUPABASE_BIND_ADDRESS

        DB_PUBLIC_LOCALHOST_PORT="$(( 3000+$DEPLOYMENT_SLOT_PORT_OFFSET*10+2 ))"
        ./devops/dotenv --file .env set DB_PUBLIC_LOCALHOST_PORT=$DB_PUBLIC_LOCALHOST_PORT

        echo "Setting Supabase Container Configuration"

        ./devops/dotenv --file .env set POSTGRES_PASSWORD=$POSTGRES_PASSWORD
        ./devops/dotenv --file .env set JWT_SECRET=$JWT_SECRET
        ./devops/dotenv --file .env set DASHBOARD_USERNAME=$DASHBOARD_USERNAME
        ./devops/dotenv --file .env set DASHBOARD_PASSWORD=$DASHBOARD_PASSWORD

        ./devops/dotenv --file .env set SITE_URL=$STATBUS_URL
        ./devops/dotenv --file .env set API_EXTERNAL_URL=$SUPABASE_URL
        ./devops/dotenv --file .env set SUPABASE_PUBLIC_URL=$SUPABASE_URL
        # Maps to GOTRUE_EXTERNAL_EMAIL_ENABLED to allow authentication with Email at all.
        # So SIGNUP really means SIGNIN
        ./devops/dotenv --file .env set ENABLE_EMAIL_SIGNUP=true
        # Allow creating users and setting the email as verified,
        # rather than sending an actual email where the user must
        # click the link.
        ./devops/dotenv --file .env set ENABLE_EMAIL_AUTOCONFIRM=true
        # Disables signup with EMAIL, when ENABLE_EMAIL_SIGNUP=true
        ./devops/dotenv --file .env set DISABLE_SIGNUP=true
        # Sets the project name in the Supabase API portal.
        ./devops/dotenv --file .env set STUDIO_DEFAULT_PROJECT="$DEPLOYMENT_SLOT_NAME"

        # Issued At Time: Current timestamp in seconds since the Unix epoch
        iat=$(date +%s)
        # Number of seconds in 5 years (5 years * 365 days/year * 24 hours/day * 60 minutes/hour * 60 seconds/minute)
        seconds_in_5_years=$((5 * 365 * 24 * 60 * 60))
        # Expiration Time: Calculate exp as iat plus the seconds in 5 years
        exp=$((iat + seconds_in_5_years))
        jwt_anon_payload=$(cat <<EOF
{
  "role": "anon",
  "iss": "supabase",
  "iat": $iat,
  "exp": $exp
}
EOF
)
        jwt_service_role_payload=$(cat <<EOF
{
  "role": "service_role",
  "iss": "supabase",
  "iat": $iat,
  "exp": $exp
}
EOF
)
        # brew install mike-engel/jwt-cli/jwt-cli
        export ANON_KEY=$(jwt encode --secret "$JWT_SECRET" "$jwt_anon_payload")
        ./devops/dotenv --file .env set ANON_KEY=$ANON_KEY

        export SERVICE_ROLE_KEY=$(jwt encode --secret "$JWT_SECRET" "$jwt_service_role_payload")
        ./devops/dotenv --file .env set SERVICE_ROLE_KEY=$SERVICE_ROLE_KEY

        ;;
     'postgres-variables' )
        PGHOST=127.0.0.1
        PGPORT=$(./devops/dotenv --file .env get DB_PUBLIC_LOCALHOST_PORT)
        PGDATABASE=$(./devops/dotenv --file .env get POSTGRES_DB)
        PGUSER=postgres
        PGPASSWORD=$(./devops/dotenv --file .env get POSTGRES_PASSWORD)
        cat <<EOS
export PGHOST=$PGHOST PGPORT=$PGPORT PGDATABASE=$PGDATABASE PGUSER=$PGUSER PGPASSWORD=$PGPASSWORD
EOS
      ;;
     'refresh' )
        echo 'select statistical_unit_refresh_now();' | ./devops/manage-statbus.sh psql
      ;;
     'psql' )
        eval $(./devops/manage-statbus.sh postgres-variables)
        # The local psql is always tried first, as it has access to files
        # used for copying in data.
        if $(which psql > /dev/null); then
          psql "$@"
        else
          # When using scripted input, such as "< some.sql" then interactive TTY is required.
          args="-i"
          if test -t 0; then
            # Enable the TTY in docker,with -t
            # as required for an interactive psql promp
            args="-ti"
          fi
          COMPOSE_INSTANCE_NAME=$(./devops/dotenv --file .env get COMPOSE_INSTANCE_NAME)
          docker compose exec $args -e PGPASSWORD db psql -U $PGUSER $PGDATABASE "$@"
        fi
      ;;
     'generate-types' )
        pushd $WORKSPACE/app
        #nvm doesn' work in a script!
        #if which fnm; then
        #    fnm use
        #else
        #    nvm use
        #fi
        eval $($WORKSPACE/devops/manage-statbus.sh postgres-variables)
        db_url="postgresql://$PGUSER:$PGPASSWORD@$PGHOST:$PGPORT/$PGDATABASE?sslmode=disable"
        # Run interactively and say 'y' for installing the latest package
        ~/.nvm/nvm-exec npx supabase@beta gen types typescript --db-url "$db_url"
        # Update the types from the database.
        ~/.nvm/nvm-exec npx supabase@beta gen types typescript --db-url "$db_url" > src/lib/database.types.ts
      ;;
     'generate-docker-compose-adjustments' )
        echo Generating docker-compose.supabase_docker.erase-ports.yml
        yq '(
          .. | # recurse through all the nodes
          select(has("ports")) | # match parents that have volume
          (.ports) | # select those children
          select(.) # filter out nulls
          | . |= "!reset []"
        ) as $i ireduce({};  # using that set of nodes, create a new result map
          setpath($i | path; $i) # and put in each node, using its original path
        ) ' supabase_docker/docker-compose.yml | tr -d "'" > docker-compose.supabase_docker.erase-ports.yml

        echo Generating docker-compose.supabase_docker.customize-container_name.yml
        yq '(
          .. | # recurse through all the nodes
          select(has("container_name")) |
          .container_name = "${COMPOSE_INSTANCE_NAME:-statbus}-" + key |
          (.container_name)
        ) as $i ireduce({};  # using that set of nodes, create a new result map
          setpath($i | path; $i) # and put in each node, using its original path
        ) ' supabase_docker/docker-compose.yml > docker-compose.supabase_docker.customize-container_name.yml

        echo Generating docker-compose.supabase_docker.add-profile.yml
        yq '(
          .services[] | # recurse through all service definitions
          .profiles = ["all", "not_app"] | # set profiles
          (.profiles) # Only retain profiles
        ) as $i ireduce({};  # using that set of nodes, create a new result map
          setpath($i | path; $i) # and put in each node, using its original path
        ) ' supabase_docker/docker-compose.yml > docker-compose.supabase_docker.add-profile.yml
      ;;
     * )
      echo "Unknown action '$action', select one of"
      awk -F "'" '/^ +''(..+)'' \)$/{print $2}' devops/manage-statbus.sh
      exit 1
      ;;
esac
