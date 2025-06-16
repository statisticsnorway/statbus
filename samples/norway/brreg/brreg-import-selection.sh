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

# Use current year for the selection import
YEAR=$(date +%Y)

echo "Creating import jobs for selection data"
# Create import job for hovedenhet (legal units) selection
$WORKSPACE/devops/manage-statbus.sh psql -c "
WITH def AS (SELECT id FROM public.import_definition where slug = 'brreg_hovedenhet_2024')
INSERT INTO public.import_job (definition_id, slug, default_valid_from, default_valid_to, description, note, user_id)
SELECT def.id,
       'import_hovedenhet_${YEAR}_selection',
       '${YEAR}-01-01'::DATE,
       'infinity'::DATE,
       'Import Job for BRREG Hovedenhet ${YEAR} Selection',
       'This job handles the import of BRREG Hovedenhet selection data for ${YEAR}.',
       (select id from public.user where email = '${USER_EMAIL}')
FROM def
ON CONFLICT (slug) DO NOTHING;"

# Create import job for underenhet (establishments) selection
$WORKSPACE/devops/manage-statbus.sh psql -c "
WITH def AS (SELECT id FROM public.import_definition where slug = 'brreg_underenhet_2024')
INSERT INTO public.import_job (definition_id, slug, default_valid_from, default_valid_to, description, note, user_id)
SELECT def.id,
       'import_underenhet_${YEAR}_selection',
       '${YEAR}-01-01'::DATE,
       'infinity'::DATE,
       'Import Job for BRREG Underenhet ${YEAR} Selection',
       'This job handles the import of BRREG Underenhet selection data for ${YEAR}.',
       (select id from public.user where email = '${USER_EMAIL}')
FROM def
ON CONFLICT (slug) DO NOTHING;"

echo "Loading data into import tables"
# Load hovedenhet (legal units) data
echo "Loading hovedenhet selection data"
$WORKSPACE/devops/manage-statbus.sh psql -c "\copy public.import_hovedenhet_${YEAR}_selection_upload FROM '$WORKSPACE/samples/norway/legal_unit/enheter-selection-cli-with-mapping-import.csv' WITH CSV HEADER;"

# Load underenhet (establishments) data
echo "Loading underenhet selection data"
$WORKSPACE/devops/manage-statbus.sh psql -c "\copy public.import_underenhet_${YEAR}_selection_upload FROM '$WORKSPACE/samples/norway/establishment/underenheter-selection-cli-with-mapping-import.csv' WITH CSV HEADER;"

echo "Checking import job states"
$WORKSPACE/devops/manage-statbus.sh psql -c "SELECT slug, state FROM public.import_job WHERE slug LIKE '%selection' ORDER BY slug;"

popd
