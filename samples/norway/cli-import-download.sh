#!/bin/bash
# samples/norway/cli-import-download.sh
#
set -e # Exit on any failure for any command

if test -n "$DEBUG"; then
  set -x # Print all commands before running them - for easy debugging.
fi

WORKSPACE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && cd ../.. && pwd)"
cd "$WORKSPACE"

# Define file paths as variables
ENHETER_FILE="${WORKSPACE}/tmp/enheter.csv"
UNDERENHETER_FILE="${WORKSPACE}/tmp/underenheter.csv"

# Only build if any of the imports are about to run
if test -f "$ENHETER_FILE" || test -f "$UNDERENHETER_FILE"; then
  pushd cli >/dev/null
  shards build
  popd >/dev/null
fi

IMPORT_FLAG=0
if test -f "$ENHETER_FILE"; then
  ./cli/bin/statbus import legal_unit -f "$ENHETER_FILE" --config "${WORKSPACE}/samples/norway/enheter-selection-cli-mapping.json" --strategy insert --skip-refresh-of-materialized-views
  IMPORT_FLAG=1
fi
if test -f "$UNDERENHETER_FILE"; then
  ./cli/bin/statbus import establishment -f "$UNDERENHETER_FILE" --config "${WORKSPACE}/samples/norway/underenheter-selection-cli-mapping.json" --strategy insert --skip-refresh-of-materialized-views
  IMPORT_FLAG=1
fi

# Run refresh only if imports were run
if test "$IMPORT_FLAG" -eq 1; then
  devops/manage-statbus.sh refresh
fi
