#!/bin/bash
#
set -e # Exit on any failure for any command

if test -n "$DEBUG"; then
  set -x # Print all commands before running them - for easy debugging.
fi

WORKSPACE="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && cd .. && pwd )"
cd $WORKSPACE

if ! test -f $WORKSPACE/supabase/docker/.env; then
  cp -f $WORKSPACE/.supabase-docker-local-development-env $WORKSPACE/supabase/docker/.env
fi

action=$1
case "$action" in
    'start-foreground' )
        cd $WORKSPACE/supabase/docker
        docker compose up
      ;;
    'start-background' )
        cd $WORKSPACE/supabase/docker
        docker compose up --detach
      ;;
    'logs' )
        cd $WORKSPACE/supabase/docker
        docker compose logs --follow
      ;;
    'ps' )
        cd $WORKSPACE/supabase/docker
        docker compose ps
      ;;
    'create-db-structure' )
        cd $WORKSPACE
        ./devops/psql-development.sh < dbseed/create-db-structure.sql 2>&1
      ;;
    'seed-db' )
        cd $WORKSPACE
        ./devops/psql-development.sh < dbseed/seed-db.sql 2>&1
      ;;
    'delete-db-structure' )
        cd $WORKSPACE
        ./devops/psql-development.sh < dbseed/delete-db-structure.sql 2>&1
      ;;
    'stop-background' )
        cd $WORKSPACE/supabase/docker
        docker compose down
      ;;
    'delete-db' )
        cd $WORKSPACE/supabase/docker
        rm -rf $WORKSPACE/supabase/docker/volumes/db/data/*
      ;;
     'upgrade' )
        cd $WORKSPACE
        git submodule update --remote --merge
      ;;
     * )
      echo "Unknown action '$action', select one of"
      awk -F "'" '/^ +''(..+)'' \)$/{print $2}' devops/manage-supabase.sh
      exit 1
      ;;
esac
