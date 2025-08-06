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

cd $WORKSPACE

legal_unit_file=$WORKSPACE/tmp/enheter.csv
establishment_file=$WORKSPACE/tmp/underenheter_filtered.csv

TODAY=$(date +%Y-%m-%d)
IMPORT_YEAR=$(date +%Y)

echo "Setting up import jobs for BRREG data with valid_from=${TODAY}"

# Check if import definitions exist, create them if not
if ! $WORKSPACE/devops/manage-statbus.sh psql -t -c "SELECT id FROM public.import_definition WHERE slug = 'brreg_hovedenhet_2025'" | grep -q .; then
  echo "Creating import definition for BRREG legal units"
  $WORKSPACE/devops/manage-statbus.sh psql < samples/norway/brreg/create-import-definition-hovedenhet-2025.sql
fi

if ! $WORKSPACE/devops/manage-statbus.sh psql -t -c "SELECT id FROM public.import_definition WHERE slug = 'brreg_underenhet_2025'" | grep -q .; then
  echo "Creating import definition for BRREG establishments"
  $WORKSPACE/devops/manage-statbus.sh psql < samples/norway/brreg/create-import-definition-underenhet-2025.sql
fi

# Create import jobs
echo "Creating import jobs for current data"

# Create import job for hovedenhet (legal units)
$WORKSPACE/devops/manage-statbus.sh psql -c "
WITH def AS (SELECT id FROM public.import_definition where slug = 'brreg_hovedenhet_2025')
INSERT INTO public.import_job (definition_id, slug, default_valid_from, default_valid_to, description, note, user_id)
SELECT def.id,
       'import_hovedenhet_2025',
       '${TODAY}'::DATE,
       'infinity'::DATE,
       'Import Job for BRREG Hovedenhet 2025 (Current)',
       'This job handles the import of current BRREG Hovedenhet data.',
       (select id from public.user where email = '${USER_EMAIL}')
FROM def
ON CONFLICT (slug) DO UPDATE SET
    default_valid_from = '${TODAY}'::DATE,
    default_valid_to = 'infinity'::DATE;"

# Create import job for underenhet (establishments)
$WORKSPACE/devops/manage-statbus.sh psql -c "
WITH def AS (SELECT id FROM public.import_definition where slug = 'brreg_underenhet_2025')
INSERT INTO public.import_job (definition_id, slug, default_valid_from, default_valid_to, description, note, user_id)
SELECT def.id,
       'import_underenhet_2025',
       '${TODAY}'::DATE,
       'infinity'::DATE,
       'Import Job for BRREG Underenhet 2025 (Current)',
       'This job handles the import of current BRREG Underenhet data.',
       (select id from public.user where email = '${USER_EMAIL}')
FROM def
ON CONFLICT (slug) DO UPDATE SET
    default_valid_from = '${TODAY}'::DATE,
    default_valid_to = 'infinity'::DATE;"

# Load data into import tables
if [ -f "$legal_unit_file" ]; then
    echo "Loading hovedenhet data"
    $WORKSPACE/devops/manage-statbus.sh psql -c "\copy public.import_hovedenhet_2025_upload FROM '$legal_unit_file' WITH CSV HEADER DELIMITER ',' QUOTE '\"' ESCAPE '\"';"
else
    echo "Warning: Legal unit file $legal_unit_file not found, skipping import"
fi

if [ -f "$establishment_file" ]; then
    echo "Loading underenhet data"
    $WORKSPACE/devops/manage-statbus.sh psql -c "\copy public.import_underenhet_2025_upload FROM '$establishment_file' WITH CSV HEADER DELIMITER ',' QUOTE '\"' ESCAPE '\"';"
else
    echo "Warning: Establishment file $establishment_file not found, skipping import"
fi

echo "Checking import job states"
$WORKSPACE/devops/manage-statbus.sh psql -c "SELECT slug, state FROM public.import_job WHERE slug IN ('import_hovedenhet_2025', 'import_underenhet_2025');"
