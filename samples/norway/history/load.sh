#!/bin/bash
#
set -e # Exit on any failure for any command

CLI_EXTRA_ARGS=""
if test -n "$DEBUG"; then
  set -x # Print all commands before running them - for easy debugging.
  CLI_EXTRA_ARGS=" --verbose"
fi

WORKSPACE="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && cd ../../.. && pwd )"

pushd $WORKSPACE

source supabase_docker/.env
export PGHOST=localhost
export PGPORT=$DB_PUBLIC_LOCALHOST_PORT
export PGDATABASE=$POSTGRES_DB
export PGUSER=postgres
export PGPASSWORD="$POSTGRES_PASSWORD"
echo "Setting up Statbus for Norway"
psql < samples/norway/setup.sql


echo "Adding tags for insert into right part of history"
psql < samples/norway/history/add-tags.sql

pushd cli
echo "Buildig cli"
shards build

YEARS=$(psql -t -c "SELECT DISTINCT year FROM gh.sample ORDER BY year;")

for YEAR in $YEARS; do
    TAG="census.$YEAR"
    echo "Loading data for year: $YEAR with $TAG"
    echo "Loading legal_units"
    time ./bin/statbus import legal_unit --tag "$TAG" -f "../samples/norway/history/${YEAR}-enheter.csv" --config ../samples/norway/enheter-selection-cli-mapping.json --strategy insert --skip-refresh-of-materialized-views --immediate-constraint-checking$CLI_EXTRA_ARGS
    echo "Loading establishments"
    time ./bin/statbus import establishment --tag "$TAG" -f "../samples/norway/history/${YEAR}-underenheter.csv" --config ../samples/norway/underenheter-selection-cli-mapping.json --strategy insert --skip-refresh-of-materialized-views --immediate-constraint-checking$CLI_EXTRA_ARGS
done

popd

popd