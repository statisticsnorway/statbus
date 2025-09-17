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

echo "Creating import jobs for demo data with source dates"
$WORKSPACE/devops/manage-statbus.sh psql -v USER_EMAIL="${USER_EMAIL}" -f samples/demo/import-demo-data-with-source-dates.sql

echo "Loading data into import tables"
# Load legal units data
echo "Loading legal units with source dates demo data"
$WORKSPACE/devops/manage-statbus.sh psql -c "\copy public.import_demo_lu_wsd_upload(tax_ident,stat_ident,name,valid_from,physical_address_part1,valid_to,postal_address_part1,postal_address_part2,physical_address_part2,physical_postcode,postal_postcode,physical_address_part3,physical_postplace,postal_address_part3,postal_postplace,phone_number,landline,mobile_number,fax_number,web_address,email_address,secondary_activity_category_code,physical_latitude,physical_longitude,physical_altitude,birth_date,physical_region_code,postal_country_iso_2,physical_country_iso_2,primary_activity_category_code,legal_form_code,sector_code,employees,turnover,data_source_code,status_code,unit_size_code) FROM '$WORKSPACE/app/public/demo/legal_units_with_source_dates_demo.csv' WITH CSV HEADER;"

# Load formal establishments data
echo "Loading formal establishments with source dates demo data"
$WORKSPACE/devops/manage-statbus.sh psql -c "\copy public.import_demo_es_for_lu_wsd_upload(tax_ident,stat_ident,name,physical_region_code,valid_from,valid_to,postal_country_iso_2,physical_country_iso_2,primary_activity_category_code,secondary_activity_category_code,employees,turnover,legal_unit_tax_ident,data_source_code,physical_address_part1,physical_address_part2,physical_address_part3,postal_address_part1,postal_address_part2,postal_address_part3,phone_number,mobile_number,landline,fax_number,web_address,email_address,physical_latitude,physical_longitude,physical_altitude,birth_date,unit_size_code,status_code) FROM '$WORKSPACE/app/public/demo/formal_establishments_units_with_source_dates_demo.csv' WITH CSV HEADER;"

# Load informal establishments data
echo "Loading informal establishments with source dates demo data"
$WORKSPACE/devops/manage-statbus.sh psql -c "\copy public.import_demo_es_without_lu_wsd_upload(tax_ident,stat_ident,name,physical_region_code,valid_from,valid_to,physical_country_iso_2,postal_country_iso_2,primary_activity_category_code,secondary_activity_category_code,employees,turnover,data_source_code,physical_address_part1,physical_address_part2,physical_address_part3,postal_address_part1,postal_address_part2,postal_address_part3,phone_number,mobile_number,landline,fax_number,web_address,email_address,unit_size_code,status_code,physical_latitude,physical_longitude,physical_altitude) FROM '$WORKSPACE/app/public/demo/informal_establishments_units_with_source_dates_demo.csv' WITH CSV HEADER;"

echo "Checking import job states"
$WORKSPACE/devops/manage-statbus.sh psql -c "SELECT slug, state FROM public.import_job WHERE slug LIKE 'import_demo_%_wsd' ORDER BY slug;"

popd
