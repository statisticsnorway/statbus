#!/bin/bash
#
# Import script for hierarchical identifier demo data
# This demonstrates hierarchical external identifiers with two examples:
# - census_ident: 4-level hierarchy (census.region.surveyor.unit_no) - Uganda use case
# - judicial_ident: 2-level hierarchy (court.unit_no) - Morocco use case
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

WORKSPACE="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && cd ../../.. && pwd )"

# Verify user exists in auth.users
if ! $WORKSPACE/devops/manage-statbus.sh psql -t -c "select id from public.user where email = '${USER_EMAIL}'" | grep -q .; then
  echo "Error: No user found with email ${USER_EMAIL}"
  exit 1
fi

if [ -n "${DEBUG:-}" ]; then
  set -x # Print all commands before running them - for easy debugging.
fi

pushd $WORKSPACE

echo "Setting up Statbus for Hierarchical Demo Data"
$WORKSPACE/devops/manage-statbus.sh psql < samples/demo/hierarchical/getting-started.sql

echo "Creating import jobs for hierarchical demo data"
$WORKSPACE/devops/manage-statbus.sh psql -v USER_EMAIL="${USER_EMAIL}" -f samples/demo/hierarchical/import-hierarchical-demo-data.sql

echo "Loading data into import tables"
# Note: Use relative paths for \copy to work both locally and in Docker
# (Docker psql runs with -w /statbus, so relative paths resolve correctly)

# Load legal units with hierarchical identifiers
# - Uganda units: census_ident (4-level)
# - Morocco units: judicial_ident (2-level)
echo "Loading legal units with hierarchical identifiers"
$WORKSPACE/devops/manage-statbus.sh psql -c "\copy public.import_hierarchical_demo_lu_current_upload(tax_ident,stat_ident,name,birth_date,physical_region_code,physical_country_iso_2,primary_activity_category_code,legal_form_code,sector_code,employees,turnover,data_source_code,census_ident_census,census_ident_region,census_ident_surveyor,census_ident_unit_no,judicial_ident_court,judicial_ident_unit_no) FROM 'samples/demo/hierarchical/legal_units_hierarchical_demo.csv' WITH CSV HEADER;"

# Load formal establishments with hierarchical identifiers
echo "Loading formal establishments with hierarchical identifiers"
$WORKSPACE/devops/manage-statbus.sh psql -c "\copy public.import_hierarchical_demo_es_for_lu_current_upload(tax_ident,stat_ident,name,physical_region_code,physical_country_iso_2,primary_activity_category_code,employees,turnover,legal_unit_tax_ident,data_source_code,census_ident_census,census_ident_region,census_ident_surveyor,census_ident_unit_no,judicial_ident_court,judicial_ident_unit_no) FROM 'samples/demo/hierarchical/formal_establishments_hierarchical_demo.csv' WITH CSV HEADER;"

echo "Checking import job states"
$WORKSPACE/devops/manage-statbus.sh psql -c "SELECT slug, state FROM public.import_job WHERE slug LIKE 'import_hierarchical_demo_%' ORDER BY slug;"

popd
