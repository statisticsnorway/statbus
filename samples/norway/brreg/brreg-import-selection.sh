#!/bin/bash
#
set -e # Exit on any failure for any command
set -u # Treat unset variables as an error

# Initialize variables with defaults
DEBUG=${DEBUG:-}

# Validate before database contact.
# shellcheck source=samples/norway/brreg/brreg-import-options.sh
source "$(dirname "${BASH_SOURCE[0]}")/brreg-import-options.sh"
brreg_parse_options "$@"
if [ "$BRREG_HELP" -eq 1 ]; then brreg_help; exit 0; fi

# Check for required USER_EMAIL environment variable
if [ -z "${USER_EMAIL:-}" ]; then
  echo "Error: USER_EMAIL environment variable must be set"
  exit 1
fi

WORKSPACE="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && cd ../../.. && pwd )"

# The database to load into: --database NAME, else the deployment's own
# database. test/import_benchmark loads a throwaway database this way.
DB_ARGS=()
if [ -n "$BRREG_DATABASE" ]; then
  DB_ARGS=(-d "$BRREG_DATABASE")
fi
sb_psql() { "$WORKSPACE/sb" psql ${DB_ARGS[@]+"${DB_ARGS[@]}"} -v ON_ERROR_STOP=1 "$@"; }

# Refuse explicit date conflicts before setup, definitions or uploads.
brreg_check_existing_validity selection

# Verify user exists in auth.users
if ! sb_psql -t -c "select id from public.user where email = '${USER_EMAIL}'" | grep -q .; then
  echo "Error: No user found with email ${USER_EMAIL}"
  exit 1
fi

if [ -n "${DEBUG:-}" ]; then
  set -x # Print all commands before running them - for easy debugging.
fi

pushd "$WORKSPACE"

echo "Setting up Statbus for Norway"
sb_psql < samples/norway/getting-started.sql

echo "Adding import definitions for BRREG units"
# NOTE: The sample data files used by this script are based on the 2024 BRREG
# format. The import definitions must match this format. Do not update to 2025
# definitions until the sample files are regenerated with the new format.
sb_psql < samples/norway/brreg/create-import-definition-hovedenhet-2024.sql
sb_psql < samples/norway/brreg/create-import-definition-underenhet-2024.sql

# Use current year only for the legacy default selection import
YEAR=${BRREG_YEAR:-$(date +%Y)}
VALID_FROM=${BRREG_VALID_FROM:-${YEAR}-01-01}

echo "Creating import jobs for selection data"
# Create import job for hovedenhet (legal units) selection
sb_psql -c "
WITH def AS (SELECT id FROM public.import_definition where slug = 'brreg_hovedenhet_2024')
INSERT INTO public.import_job (definition_id, slug, default_valid_from, default_valid_to, description, note, user_id, review)
SELECT def.id,
       'import_hovedenhet_${YEAR}_selection',
       '${VALID_FROM}'::DATE,
       'infinity'::DATE,
       'Import Job for BRREG Hovedenhet ${YEAR} Selection',
       'This job handles the import of BRREG Hovedenhet selection data for ${YEAR}.',
       (select id from public.user where email = '${USER_EMAIL}'),
       false
FROM def
ON CONFLICT (slug) DO NOTHING;"

# Create import job for underenhet (establishments) selection
sb_psql -c "
WITH def AS (SELECT id FROM public.import_definition where slug = 'brreg_underenhet_2024')
INSERT INTO public.import_job (definition_id, slug, default_valid_from, default_valid_to, description, note, user_id, review)
SELECT def.id,
       'import_underenhet_${YEAR}_selection',
       '${VALID_FROM}'::DATE,
       'infinity'::DATE,
       'Import Job for BRREG Underenhet ${YEAR} Selection',
       'This job handles the import of BRREG Underenhet selection data for ${YEAR}.',
       (select id from public.user where email = '${USER_EMAIL}'),
       false
FROM def
ON CONFLICT (slug) DO NOTHING;"

echo "Loading data into import tables"
# Note: Use relative paths for \copy to work both locally and in Docker
# (Docker psql runs with -w /statbus, so relative paths resolve correctly)
# Load hovedenhet (legal units) data
echo "Loading hovedenhet selection data"
sb_psql -c "\copy public.import_hovedenhet_${YEAR}_selection_upload FROM 'samples/norway/legal_unit/enheter-selection.csv' WITH CSV HEADER;"

# Load underenhet (establishments) data
echo "Loading underenhet selection data"
sb_psql -c "\copy public.import_underenhet_${YEAR}_selection_upload FROM 'samples/norway/establishment/underenheter-selection.csv' WITH CSV HEADER;"

# Import roller (legal relationships) selection
echo "Seeding legal relationship types"
sb_psql < samples/norway/brreg/seed-legal-rel-types.sql

echo "Adding import definition for BRREG roller (legal relationships)"
sb_psql < samples/norway/brreg/create-import-definition-roller-2025.sql

echo "Creating import job for roller selection data"
sb_psql -c "
WITH def AS (SELECT id FROM public.import_definition where slug = 'brreg_roller_2025')
INSERT INTO public.import_job (definition_id, slug, default_valid_from, default_valid_to, description, note, user_id, review)
SELECT def.id,
       'import_roller_${YEAR}_selection',
       '${VALID_FROM}'::DATE,
       'infinity'::DATE,
       'Import Job for BRREG Roller ${YEAR} Selection',
       'This job imports org-to-org controlling relationships from BRREG roller selection data.',
       (select id from public.user where email = '${USER_EMAIL}'),
       false
FROM def
ON CONFLICT (slug) DO NOTHING;"

echo "Loading roller selection data"
sb_psql -c "\copy public.import_roller_${YEAR}_selection_upload FROM 'samples/norway/legal_relationship/roller-selection.csv' WITH CSV HEADER;"

echo "Checking import job states"
sb_psql -c "SELECT slug, state FROM public.import_job WHERE slug LIKE '%selection' ORDER BY slug;"

popd
