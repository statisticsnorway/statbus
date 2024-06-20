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

echo "Setting up Statbus for Norway"
./devops/manage-statbus.sh psql < samples/norway/setup.sql


echo "Adding tags for insert into right part of history"
./devops/manage-statbus.sh psql < samples/norway/small-history/add-tags.sql

pushd cli
echo "Buildig cli"
shards build

YEARS=$(ls $WORKSPACE/samples/norway/small-history/*-enheter.csv | sed -E 's/.*\/([0-9]{4})-enheter\.csv/\1/' | sort -u)

for YEAR in $YEARS; do
    TAG="census.$YEAR"
    echo "Loading data for year: $YEAR with $TAG"
    echo "Loading legal_units"
    time ./bin/statbus import legal_unit --tag "$TAG" -f "../samples/norway/small-history/${YEAR}-enheter.csv" --config ../samples/norway/enheter-selection-cli-mapping.json --strategy insert --skip-refresh-of-materialized-views --immediate-constraint-checking$CLI_EXTRA_ARGS
    echo "Loading establishments"
    time ./bin/statbus import establishment --tag "$TAG" -f "../samples/norway/small-history/${YEAR}-underenheter.csv" --config ../samples/norway/underenheter-selection-cli-mapping.json --strategy insert --skip-refresh-of-materialized-views --immediate-constraint-checking$CLI_EXTRA_ARGS
done

popd

./devops/manage-statbus.sh psql <<EOS
SELECT statistical_unit_refresh_now();
EOS

popd