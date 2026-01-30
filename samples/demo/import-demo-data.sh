#!/bin/bash
#
set -e # Exit on any failure for any command
set -u # Treat unset variables as an error

# Initialize variables with defaults
DEBUG=${DEBUG:-}

# Check for required USER_EMAIL environment variable
if [ -z "${USER_EMAIL:-}" ]; then
  echo "Error: USER_EMAIL environment variable must be set"
  exit 1
fi

WORKSPACE="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && cd ../.. && pwd )"

# Verify user exists in auth.users
if ! $WORKSPACE/devops/manage-statbus.sh psql -t -c "select id from public.user where email = '${USER_EMAIL}'" | grep -q .; then
  echo "Error: No user found with email ${USER_EMAIL}"
  exit 1
fi

if [ -n "${DEBUG:-}" ]; then
  set -x # Print all commands before running them - for easy debugging.
fi

pushd $WORKSPACE

echo "Setting up Statbus for Demo Data"
$WORKSPACE/devops/manage-statbus.sh psql < samples/demo/getting-started.sql

echo "Creating import jobs for demo data"
$WORKSPACE/devops/manage-statbus.sh psql -v USER_EMAIL="${USER_EMAIL}" -f samples/demo/import-demo-data.sql

echo "Loading data into import tables"
# Note: Use relative paths for \copy to work both locally and in Docker
# (Docker psql runs with -w /statbus, so relative paths resolve correctly)
# Load legal units data
echo "Loading legal units demo data"
$WORKSPACE/devops/manage-statbus.sh psql -c "\copy public.import_demo_lu_current_upload(tax_ident,stat_ident,name,birth_date,physical_region_code,physical_country_iso_2,primary_activity_category_code,legal_form_code,sector_code,employees,turnover,data_source_code) FROM 'app/public/demo/legal_units_demo.csv' WITH CSV HEADER;"

# Load formal establishments data
echo "Loading formal establishments demo data"
$WORKSPACE/devops/manage-statbus.sh psql -c "\copy public.import_demo_es_for_lu_current_upload(tax_ident,stat_ident,name,physical_region_code,physical_country_iso_2,primary_activity_category_code,employees,turnover,legal_unit_tax_ident,data_source_code) FROM 'app/public/demo/formal_establishments_units_demo.csv' WITH CSV HEADER;"

# Load informal establishments data
echo "Loading informal establishments demo data"
$WORKSPACE/devops/manage-statbus.sh psql -c "\copy public.import_demo_es_without_lu_current_upload(tax_ident,stat_ident,name,physical_region_code,physical_country_iso_2,primary_activity_category_code,employees,turnover,data_source_code) FROM 'app/public/demo/informal_establishments_units_demo.csv' WITH CSV HEADER;"

echo "Checking import job states"
$WORKSPACE/devops/manage-statbus.sh psql -c "SELECT slug, state FROM public.import_job WHERE slug LIKE 'import_demo_%_current' ORDER BY slug;"

popd
