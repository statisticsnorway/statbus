#!/bin/bash
#
set -e # Exit on any failure for any command

if test -n "$DEBUG"; then
  set -x # Print all commands before running them - for easy debugging.
fi

WORKSPACE="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && cd ../../.. && pwd )"

pushd $WORKSPACE

echo "Setting up Statbus for Norway"
./devops/manage-statbus.sh psql < $WORKSPACE/samples/norway/getting-started.sql

pushd cli
echo "Loading legal_units"
shards build && time ./bin/statbus import legal_unit -f ../samples/norway/legal_unit/enheter-selection-cli-with-mapping-import.csv --config ../samples/norway/legal_unit/enheter-selection-cli-mapping.json --strategy insert
echo "Loading establishments"
shards build && time ./bin/statbus import establishment -f ../samples/norway/establishment/underenheter-selection-cli-with-mapping-import.csv --config ../samples/norway/establishment/underenheter-selection-cli-mapping.json --strategy insert
popd

popd
