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
brreg_check_existing_validity downloads

# Verify user exists in auth.users
if ! sb_psql -t -c "select id from public.user where email = '${USER_EMAIL}'" | grep -q .; then
  echo "Error: No user found with email ${USER_EMAIL}"
  exit 1
fi

if [ -n "${DEBUG:-}" ]; then
  set -x # Print all commands before running them - for easy debugging.
fi

cd "$WORKSPACE"

echo "Setting up Statbus for Norway"
sb_psql < samples/norway/getting-started.sql

legal_unit_file=$WORKSPACE/tmp/enheter.csv
establishment_file=$WORKSPACE/tmp/underenheter_filtered.csv

TODAY=${BRREG_VALID_FROM:-$(date +%Y-%m-%d)}

echo "Setting up import jobs for BRREG data with valid_from=${TODAY}"

# Check if import definitions exist, create them if not
if ! sb_psql -t -c "SELECT id FROM public.import_definition WHERE slug = 'brreg_hovedenhet_2025'" | grep -q .; then
  echo "Creating import definition for BRREG legal units"
  sb_psql < samples/norway/brreg/create-import-definition-hovedenhet-2025.sql
fi

if ! sb_psql -t -c "SELECT id FROM public.import_definition WHERE slug = 'brreg_underenhet_2025'" | grep -q .; then
  echo "Creating import definition for BRREG establishments"
  sb_psql < samples/norway/brreg/create-import-definition-underenhet-2025.sql
fi

# Create import jobs
echo "Creating import jobs for current data"

# Create import job for hovedenhet (legal units)
sb_psql -c "
WITH def AS (SELECT id FROM public.import_definition where slug = 'brreg_hovedenhet_2025')
INSERT INTO public.import_job (definition_id, slug, default_valid_from, default_valid_to, description, note, user_id, review)
SELECT def.id,
       'import_hovedenhet_2025',
       '${TODAY}'::DATE,
       'infinity'::DATE,
       'Import Job for BRREG Hovedenhet 2025 (Current)',
       'This job handles the import of current BRREG Hovedenhet data.',
       (select id from public.user where email = '${USER_EMAIL}'),
       false
FROM def
ON CONFLICT (slug) DO UPDATE SET
    default_valid_from = '${TODAY}'::DATE,
    default_valid_to = 'infinity'::DATE,
    review = false;"

# Create import job for underenhet (establishments)
sb_psql -c "
WITH def AS (SELECT id FROM public.import_definition where slug = 'brreg_underenhet_2025')
INSERT INTO public.import_job (definition_id, slug, default_valid_from, default_valid_to, description, note, user_id, review)
SELECT def.id,
       'import_underenhet_2025',
       '${TODAY}'::DATE,
       'infinity'::DATE,
       'Import Job for BRREG Underenhet 2025 (Current)',
       'This job handles the import of current BRREG Underenhet data.',
       (select id from public.user where email = '${USER_EMAIL}'),
       false
FROM def
ON CONFLICT (slug) DO UPDATE SET
    default_valid_from = '${TODAY}'::DATE,
    default_valid_to = 'infinity'::DATE,
    review = false;"

# Load data into import tables. A job's upload table takes columns by position, so
# each file is fitted to its definition's source columns first, as the monthly
# intake does (brreg-fit-csv.py): BRREG's download columns change over time, and
# status_code is derived from BRREG's flags, not read from the file.
fit_to_definition() { # definition_slug source fitted [fit options...]
  local slug=$1 source=$2 fitted=$3; shift 3
  sb_psql -t -A -c "SELECT sc.column_name FROM public.import_source_column sc JOIN public.import_definition d ON d.id = sc.definition_id WHERE d.slug = '${slug}' ORDER BY sc.priority;" > "$fitted.columns"
  [ -s "$fitted.columns" ] || { echo "Error: import definition ${slug} has no source columns" >&2; exit 1; }
  python3 "$WORKSPACE/samples/norway/brreg/brreg-fit-csv.py" --columns "$fitted.columns" --in "$source" --out "$fitted" "$@"
}
if [ -f "$legal_unit_file" ]; then
    echo "Loading hovedenhet data"
    fit_to_definition brreg_hovedenhet_2025 "$legal_unit_file" "$WORKSPACE/tmp/enheter-fitted.csv" --derive-status
    sb_psql -c "\copy public.import_hovedenhet_2025_upload FROM 'tmp/enheter-fitted.csv' WITH CSV HEADER DELIMITER ',' QUOTE '\"' ESCAPE '\"';"
else
    echo "Warning: Legal unit file $legal_unit_file not found, skipping import"
fi

if [ -f "$establishment_file" ]; then
    echo "Loading underenhet data"
    fit_to_definition brreg_underenhet_2025 "$establishment_file" "$WORKSPACE/tmp/underenheter-fitted.csv"
    sb_psql -c "\copy public.import_underenhet_2025_upload FROM 'tmp/underenheter-fitted.csv' WITH CSV HEADER DELIMITER ',' QUOTE '\"' ESCAPE '\"';"
else
    echo "Warning: Establishment file $establishment_file not found, skipping import"
fi

# Import roller (legal relationships)
roller_file=$WORKSPACE/tmp/roller_legal_relationships.csv
if [ -f "$roller_file" ]; then
    # Seed legal relationship types
    echo "Seeding legal relationship types"
    sb_psql < samples/norway/brreg/seed-legal-rel-types.sql

    # Check/create import definition
    if ! sb_psql -t -c "SELECT id FROM public.import_definition WHERE slug = 'brreg_roller_2025'" | grep -q .; then
        echo "Creating import definition for BRREG roller (legal relationships)"
        sb_psql < samples/norway/brreg/create-import-definition-roller-2025.sql
    fi

    # Create import job
    sb_psql -c "
    WITH def AS (SELECT id FROM public.import_definition where slug = 'brreg_roller_2025')
    INSERT INTO public.import_job (definition_id, slug, default_valid_from, default_valid_to, description, note, user_id, review)
    SELECT def.id,
           'import_roller_2025',
           '${TODAY}'::DATE,
           'infinity'::DATE,
           'Import Job for BRREG Roller 2025 (Legal Relationships)',
           'This job imports org-to-org controlling relationships from BRREG roller data.',
           (select id from public.user where email = '${USER_EMAIL}'),
           false
    FROM def
    ON CONFLICT (slug) DO UPDATE SET
        default_valid_from = '${TODAY}'::DATE,
        default_valid_to = 'infinity'::DATE,
        review = false;"

    # Load data
    echo "Loading roller (legal relationships) data"
    sb_psql -c "\copy public.import_roller_2025_upload FROM 'tmp/roller_legal_relationships.csv' WITH CSV HEADER DELIMITER ',' QUOTE '\"' ESCAPE '\"';"
fi

echo "Checking import job states"
sb_psql -c "SELECT slug, state FROM public.import_job WHERE slug IN ('import_hovedenhet_2025', 'import_underenhet_2025', 'import_roller_2025');"
