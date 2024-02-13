#!/bin/bash
#
set -e # Exit on any failure for any command

if test -n "$DEBUG"; then
  set -x # Print all commands before running them - for easy debugging.
fi

WORKSPACE="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && cd ../.. && pwd )"

cd $WORKSPACE

pushd cli

shards build
./bin/statbus import legal_unit -f ../samples/norway/enheter-selection-cli-with-mapping-import.csv --config ../samples/norway/enheter-selection-cli-mapping.json --strategy insert
./bin/statbus import establishment -f ../samples/norway/underenheter-selection-cli-with-mapping-import.csv --config ../samples/norway/underenheter-selection-cli-mapping.json --strategy insert
