#!/bin/bash
#
set -e # Exit on any failure for any command

if test -n "$DEBUG"; then
  set -x # Print all commands before running them - for easy debugging.
fi

WORKSPACE="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && cd .. && pwd )"

source $WORKSPACE/.env-psql-development.sh

if $(which psql > /dev/null); then
  psql
else
  # When using scripted input, such as "< some.sql" then interactive TTY is required.
  args="-i"
  if test -t 0; then
    # Enable the TTY in docker,with -t
    # as required for an interactive psql promp
    args="-ti"
  fi
  docker exec $args $(docker ps  | awk '/statbus-db/{print $1}') psql -U $PGUSER $PGDATABASE $@
fi