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
#./devops/manage-statbus.sh activate_sql_saga
#./devops/manage-statbus.sh create-db-structure
#./devops/manage-statbus.sh create-users

# Make PG* variables available
eval $($WORKSPACE/devops/manage-statbus.sh postgres-variables)

# Directory setup for pg_regress
PG_REGRESS_DIR="$WORKSPACE/test"
PG_REGRESS_INPUT_DIR="$PG_REGRESS_DIR/sql"
PG_REGRESS_EXPECTED_DIR="$PG_REGRESS_DIR/expected"
PG_REGRESS_OUTPUT_DIR="$PG_REGRESS_DIR/results"
PG_REGRESS=`pg_config --libdir`/postgresql/pgxs/src/test/regress/pg_regress


# Ensure the test directories exist
if ! test -d $PG_REGRESS_INPUT_DIR; then
  mkdir -p "$PG_REGRESS_INPUT_DIR"
fi
if ! test -d $PG_REGRESS_EXPECTED_DIR; then
  mkdir -p "$PG_REGRESS_EXPECTED_DIR"
fi
if ! test -d $PG_REGRESS_OUTPUT_DIR; then
  mkdir -p "$PG_REGRESS_OUTPUT_DIR"
fi

# Example SQL test and expected files
SAMPLE_INPUT="$PG_REGRESS_INPUT_DIR/test.sql"
if ! test -f $SAMPLE_INPUT; then
  cat > $SAMPLE_INPUT <<EOS
SELECT 1 AS test;
EOS
fi
SAMPLE_OUTPUT="$PG_REGRESS_EXPECTED_DIR/test.out"
if ! test -f $SAMPLE_OUTPUT; then
  cat > $SAMPLE_OUTPUT <<EOS
SELECT 1 AS test;
 test 
------
    1
(1 row)

EOS
fi

#if [ "${DEBUG:-}" = "true" ]; then
#  $PG_REGRESS --help
#fi

# pg_regress uses files in the current working directory.
pushd $PG_REGRESS_DIR
# Run the regression tests with database connection details

TEST_BASENAMES=$(for file in "$PG_REGRESS_INPUT_DIR"/*.sql; do basename ${file} .sql; done)
echo "TEST_BASENAMES=$TEST_BASENAMES"

#    --launcher="../devops/manage-statbus.sh psql" \
$PG_REGRESS \
    --use-existing \
    --bindir=`pg_config --bindir` \
    --dbname=$PGDATABASE \
    --host=$PGHOST \
    --port=$PGPORT \
    --user=$PGUSER \
    --debug \
    $TEST_BASENAMES
# If you are testing an extension, load it here
# Cleanup commented out for debugging purposes
# rm -rf "$PG_REGRESS_INPUT_DIR" "$PG_REGRESS_EXPECTED_DIR" "$PG_REGRESS_OUTPUT_DIR"
