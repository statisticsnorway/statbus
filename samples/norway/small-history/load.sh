#!/bin/bash
#
set -e # Exit on any failure for any command
set -u # Treat unset variables as an error

# Initialize variables with defaults
CLI_EXTRA_ARGS=""
DEBUG=${DEBUG:-}

# Check for required USER_EMAIL environment variable
if [ -z "${USER_EMAIL:-}" ]; then
  echo "Error: USER_EMAIL environment variable must be set"
  exit 1
fi

WORKSPACE="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && cd ../../.. && pwd )"

# Verify user exists in auth.users
if ! $WORKSPACE/devops/manage-statbus.sh psql -t -c "select id from public.user where email = '${USER_EMAIL}'" | grep -q .; then
  echo "Error: No user found with email ${USER_EMAIL}"
  exit 1
fi

if [ -n "${DEBUG:-}" ]; then
  set -x # Print all commands before running them - for easy debugging.
  CLI_EXTRA_ARGS=" --verbose"
fi

pushd $WORKSPACE

echo "Setting up Statbus for Norway"
$WORKSPACE/devops/manage-statbus.sh psql < samples/norway/getting-started.sql

echo "Adding import definitions for BRREG units"
$WORKSPACE/devops/manage-statbus.sh psql < samples/norway/brreg/create-import-definition-hovedenhet-2024.sql
$WORKSPACE/devops/manage-statbus.sh psql < samples/norway/brreg/create-import-definition-underenhet-2024.sql

YEARS=$(ls $WORKSPACE/samples/norway/small-history/*-enheter.csv | sed -E 's/.*\/([0-9]{4})-enheter\.csv/\1/' | sort -u)

echo "Creating import jobs for each year"
for YEAR in $YEARS; do
    echo "Creating import jobs for year: $YEAR"

    # Create import jobs for hovedenhet (legal units)
    $WORKSPACE/devops/manage-statbus.sh psql -c "
    WITH def AS (SELECT id FROM public.import_definition where slug = 'brreg_hovedenhet_2024')
    INSERT INTO public.import_job (definition_id, slug, default_valid_from, default_valid_to, description, note, user_id)
    SELECT def.id,
           'import_hovedenhet_${YEAR}_small_history',
           '${YEAR}-01-01'::DATE,
           'infinity'::DATE,
           'Import Job for BRREG Hovedenhet ${YEAR} Small History',
           'This job handles the import of BRREG Hovedenhet small history data for ${YEAR}.',
           (select id from public.user where email = '${USER_EMAIL}')
    FROM def
    ON CONFLICT (slug) DO NOTHING;"

    # Create import jobs for underenhet (establishments)
    $WORKSPACE/devops/manage-statbus.sh psql -c "
    WITH def AS (SELECT id FROM public.import_definition where slug = 'brreg_underenhet_2024')
    INSERT INTO public.import_job (definition_id, slug, default_valid_from, default_valid_to, description, note, user_id)
    SELECT def.id,
           'import_underenhet_${YEAR}_small_history',
           '${YEAR}-01-01'::DATE,
           'infinity'::DATE,
           'Import Job for BRREG Underenhet ${YEAR} Small History',
           'This job handles the import of BRREG Underenhet small history data for ${YEAR}.',
           (select id from public.user where email = '${USER_EMAIL}')
    FROM def
    ON CONFLICT (slug) DO NOTHING;"
done

echo "Disabling RLS on import tables to support data loading"
for YEAR in $YEARS; do
    # Disable RLS on hovedenhet (legal units) upload tables
    $WORKSPACE/devops/manage-statbus.sh psql -c "ALTER TABLE public.import_hovedenhet_${YEAR}_small_history_upload DISABLE ROW LEVEL SECURITY;"

    # Disable RLS on underenhet (establishments) upload tables
    $WORKSPACE/devops/manage-statbus.sh psql -c "ALTER TABLE public.import_underenhet_${YEAR}_small_history_upload DISABLE ROW LEVEL SECURITY;"
done

echo "Loading data into import tables"
for YEAR in $YEARS; do
    echo "Loading data for year: $YEAR"

    # Load hovedenhet (legal units) data
    echo "Loading hovedenhet data for $YEAR"
    $WORKSPACE/devops/manage-statbus.sh psql -c "\copy public.import_hovedenhet_${YEAR}_small_history_upload FROM '$WORKSPACE/samples/norway/small-history/${YEAR}-enheter.csv' WITH CSV HEADER;"

    # Load underenhet (establishments) data
    echo "Loading underenhet data for $YEAR"
    $WORKSPACE/devops/manage-statbus.sh psql -c "\copy public.import_underenhet_${YEAR}_small_history_upload FROM '$WORKSPACE/samples/norway/small-history/${YEAR}-underenheter.csv' WITH CSV HEADER;"
done

#echo "Running worker processing to process import jobs"
#$WORKSPACE/devops/manage-statbus.sh psql -c "SELECT worker.process_tasks();"

echo "Checking import job states"
$WORKSPACE/devops/manage-statbus.sh psql -c "SELECT slug, state FROM public.import_job WHERE slug LIKE '%small_history' ORDER BY slug;"

popd
