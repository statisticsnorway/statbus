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

cd $WORKSPACE/supabase/docker

action=$1
case "$action" in
    'start-foreground' )
        docker compose up
      ;;
    'start-background' )
        docker compose up --detach
      ;;
    'logs' )
        docker compose logs --follow
      ;;
    'stop-background' )
        docker compose down
      ;;
    'delete-db' )
        rm -rf $WORKSPACE/supabase/docker/volumes/db/data/*
      ;;
     'upgrade' )
        cd $WORKSPACE
        git submodule update --remote --merge
      ;;
     * )
      echo "Unknown action '$action', select one of start-foreground start-background stop-background logs delete-db upgrade"
      exit 1
      ;;
esac
