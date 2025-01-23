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
./devops/manage-statbus.sh psql < $WORKSPACE/samples/norway/getting-started.sql

pushd cli
echo "Loading legal_units"
shards build && time ./bin/statbus import legal_unit --user "$USER_EMAIL" -f ../samples/norway/legal_unit/enheter-selection-cli-with-mapping-import.csv --config ../samples/norway/legal_unit/enheter-selection-cli-mapping.json --strategy insert$CLI_EXTRA_ARGS
echo "Loading establishments"
shards build && time ./bin/statbus import establishment --user "$USER_EMAIL" -f ../samples/norway/establishment/underenheter-selection-cli-with-mapping-import.csv --config ../samples/norway/establishment/underenheter-selection-cli-mapping.json --strategy insert$CLI_EXTRA_ARGS
popd

popd
