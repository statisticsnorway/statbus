#!/bin/bash
#
set -e # Exit on any failure for any command

if test -n "$DEBUG"; then
  set -x # Print all commands before running them - for easy debugging.
fi

WORKSPACE="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && cd ../../.. && pwd )"

cd $WORKSPACE

legal_unit_file=$WORKSPACE/tmp/enheter.csv
establishment_file=$WORKSPACE/tmp/underenheter_filtered.csv

pushd cli

shards build

if [ -f "$legal_unit_file" ]; then
    ./bin/statbus import legal_unit -f "$legal_unit_file" --config ${WORKSPACE}/samples/norway/legal_unit/enheter-selection-cli-mapping.json --strategy insert
else
    echo "Warning: Legal unit file $legal_unit_file not found, skipping import"
fi

if [ -f "$establishment_file" ]; then
    ./bin/statbus import establishment -f "$establishment_file" --config ${WORKSPACE}/samples/norway/establishment/underenheter-selection-cli-mapping.json --strategy insert
else
    echo "Warning: Establishment file $establishment_file not found, skipping import"
fi
