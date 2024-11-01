#!/bin/bash
#
set -e # Exit on any failure for any command

if test -n "$DEBUG"; then
  set -x # Print all commands before running them - for easy debugging.
fi

WORKSPACE="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && cd .. && pwd )"

pushd $WORKSPACE

source .env-psql-development.sh
psql < dbseed/delete-db-structure.sql 2>&1
psql < dbseed/create-db-structure.sql 2>&1
psql < samples/norway/getting-started.sql

popd
