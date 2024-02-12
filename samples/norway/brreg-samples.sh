#!/bin/bash
#
set -e # Exit on any failure for any command

if test -n "$DEBUG"; then
  set -x # Print all commands before running them - for easy debugging.
fi

WORKSPACE="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && cd ../.. && pwd )"

pushd $WORKSPACE

source supabase_docker/.env
export PGHOST=localhost
export PGPORT=$DB_PUBLIC_LOCALHOST_PORT
export PGDATABASE=$POSTGRES_DB
export PGUSER=postgres
export PGPASSWORD="$POSTGRES_PASSWORD"
echo "Setting up Statbus for Norway"
psql < samples/norway/setup.sql

pushd cli
echo "Loading legal_units"
shards build && time ./bin/statbus import legal_unit -f ../samples/norway/enheter-selection.csv --config ../samples/norway/enheter-mapping.json --strategy insert
echo "Loading establishments"
shards build && time ./bin/statbus import establishment -f ../samples/norway/underenheter-selection.csv --config ../samples/norway/underenheter-mapping.json --strategy insert
popd

popd