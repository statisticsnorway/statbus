#!/bin/bash
#
set -e # Exit on any failure for any command

CLI_EXTRA_ARGS=""
# Check for required USER_EMAIL environment variable
if [ -z "${USER_EMAIL}" ]; then
  echo "Error: USER_EMAIL environment variable must be set"
  exit 1
fi

# Verify user exists in auth.users
if ! ./devops/manage-statbus.sh psql -t -c "SELECT id FROM auth.users WHERE email = '${USER_EMAIL}'" | grep -q .; then
  echo "Error: No user found with email ${USER_EMAIL}"
  exit 1
fi
if test -n "$DEBUG"; then
  set -x # Print all commands before running them - for easy debugging.
  CLI_EXTRA_ARGS=" --verbose"
fi

WORKSPACE="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && cd ../../.. && pwd )"

pushd $WORKSPACE

echo "Setting up Statbus for Norway"
./devops/manage-statbus.sh psql < samples/norway/getting-started.sql


echo "Adding tags for insert into right part of history"
./devops/manage-statbus.sh psql < samples/norway/history/add-tags.sql

pushd cli
echo "Buildig cli"
shards build

YEARS=$(ls $WORKSPACE/samples/norway/history/*-enheter.csv | sed -E 's/.*\/([0-9]{4})-enheter\.csv/\1/' | sort -u)

for YEAR in $YEARS; do
    TAG="census.$YEAR"
    echo "Loading data for year: $YEAR with $TAG"
    echo "Loading legal_units"
    time ./bin/statbus import legal_unit --user "$USER_EMAIL" --tag "$TAG" -f "../samples/norway/history/${YEAR}-enheter.csv" --config ../samples/norway/legal_unit/enheter-selection-cli-mapping.json --strategy insert --skip-refresh-of-materialized-views --immediate-constraint-checking$CLI_EXTRA_ARGS
    echo "Loading establishments"
    time ./bin/statbus import establishment --user "$USER_EMAIL" --tag "$TAG" -f "../samples/norway/history/${YEAR}-underenheter.csv" --config ../samples/norway/establishment/underenheter-selection-cli-mapping.json --strategy insert --skip-refresh-of-materialized-views --immediate-constraint-checking$CLI_EXTRA_ARGS
done

popd

popd
