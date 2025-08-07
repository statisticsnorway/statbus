#!/bin/bash
# test/run.sh

set -euo pipefail

# Check for DEBUG environment variable
if [ "${DEBUG:-}" = "true" ]; then
  set -x # Print all commands before running them if DEBUG is true
fi

# Load environment variables from your project's configuration
WORKSPACE="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && cd .. && pwd )"

# TODO: Setup and prepare the test database.
#./devops/manage-statbus.sh start
#./devops/manage-statbus.sh create-db-structure
#./devops/manage-statbus.sh create-users

# Make PG* variables available
eval $($WORKSPACE/devops/manage-statbus.sh postgres-variables)

# Directory setup for pg_regress
PG_REGRESS_DIR="$WORKSPACE/test"
PG_REGRESS=`pg_config --libdir`/postgresql/pgxs/src/test/regress/pg_regress

for suffix in "sql" "expected" "results"; do
  if ! test -d "$PG_REGRESS_DIR/$suffix"; then
    mkdir -p "$PG_REGRESS_DIR/$suffix"
  fi
done

# The tests can reference files relative to the root of the project.
pushd $WORKSPACE

TEST_BASENAMES="$@"
if test -z "$TEST_BASENAMES"; then
  TEST_BASENAMES=$(basename -s .sql "$PG_REGRESS_DIR/sql"/*.sql)
fi

# Check if the expected output file exists, and create it if it doesn't
for test_basename in $TEST_BASENAMES; do
  expected_file="$PG_REGRESS_DIR/expected/$test_basename.out"
  if [ ! -f "$expected_file" ]; then
    echo "Warning: Expected output file $expected_file not found. Creating an empty placeholder."
    touch "$expected_file"
  fi
done

# Run the regression tests with database connection details
$PG_REGRESS \
    --use-existing \
    --bindir=`pg_config --bindir` \
    --inputdir=$PG_REGRESS_DIR \
    --expecteddir=$PG_REGRESS_DIR \
    --outputdir=$PG_REGRESS_DIR \
    --dbname=$PGDATABASE \
    --host=$PGHOST \
    --port=$PGPORT \
    --user=$PGUSER \
    --debug \
    $TEST_BASENAMES
