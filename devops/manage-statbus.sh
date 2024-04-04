#!/bin/bash
#
set -e # Exit on any failure for any command

if test -n "$DEBUG"; then
  set -x # Print all commands before running them - for easy debugging.
fi

WORKSPACE="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && cd .. && pwd )"
cd $WORKSPACE

#### TODO: Replace this with a proper .env generator.
# if ! test -f $WORKSPACE/supabase_docker/.env; then
#   cp -f $WORKSPACE/.supabase-docker-local-development-env $WORKSPACE/supabase_docker/.env
# fi
# if ! test -f $WORKSPACE/.env; then
#     # TODO: Improve generato
#   cat > $WORKSPACE/.env <<EOS
# COMPOSE_FILE=docker-compose.app.yml
# COMPOSE_INSTANCE_NAME=statbus-dev
# PUBLIC_PORT=127.0.0.1:3000
# SUPABASE_ANON_KEY=...
# SUPABASE_URL=...
# EOS
#   echo "Edit .env and adjust the variables as required."
# fi

action=$1
case "$action" in
    'start' )
        docker compose up --detach
      ;;
    'stop' )
        docker compose down
      ;;
    'logs' )
        docker compose logs --follow
      ;;
    'ps' )
        docker compose ps
      ;;
    'create-db-structure' )
        ./devops/psql-development.sh < dbseed/create-db-structure.sql 2>&1
      ;;
    'delete-db-structure' )
        ./devops/psql-development.sh < dbseed/delete-db-structure.sql 2>&1
      ;;
    'seed-db' )
        ./devops/psql-development.sh < dbseed/seed-db.sql 2>&1
      ;;
    'delete-db' )
        rm -rf $WORKSPACE/supabase_docker/volumes/db/data/*
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
     'generate-types' )
        source $WORKSPACE/.env-psql-development.sh
        cd $WORKSPACE/app
        #nvm use
        db_url="postgresql://$PGUSER:$PGPASSWORD@$PGHOST:$PGPORT/$PGDATABASE?sslmode=disable"
        ~/.nvm/nvm-exec npx supabase@beta gen types typescript --db-url "$db_url" > src/lib/database.types.ts
      ;;
     'generate-docker-compose-adjustments' )
        echo Generating docker-compose.supabase_docker.customize-container_name.yml
        yq '(
          .. | # recurse through all the nodes
          select(has("container_name")) |
          .container_name = "${COMPOSE_INSTANCE_NAME:-statbus}-" + key |
          (.container_name)
        ) as $i ireduce({};  # using that set of nodes, create a new result map
          setpath($i | path; $i) # and put in each node, using its original path
        ) ' supabase_docker/docker-compose.yml > docker-compose.supabase_docker.customize-container_name.yml

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

      ;;
     * )
      echo "Unknown action '$action', select one of"
      awk -F "'" '/^ +''(..+)'' \)$/{print $2}' devops/manage-statbus.sh
      exit 1
      ;;
esac
