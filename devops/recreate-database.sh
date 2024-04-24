#!/bin/bash
#
set -e # Exit on any failure for any command

if test -n "$DEBUG"; then
  set -x # Print all commands before running them - for easy debugging.
fi

WORKSPACE="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && cd .. && pwd )"

cd $WORKSPACE

echo Recreate the backend with the lastest database structures
./devops/manage-statbus.sh stop
./devops/manage-statbus.sh delete-db
./devops/manage-statbus.sh start

export $(awk -F= '/^[^#]/{output=output" "$1"="$2} END {print output}' .env)

echo "Wait for admin api (gotrue) to start"
starting=true
while $starting; do
	sleep 1
	curl "http://$SUPABASE_BIND_ADDRESS/auth/v1/health" \
	-H 'accept: application/json' \
	-H "apikey: $SERVICE_ROLE_KEY" && starting=false
done

echo Create users for the developers
echo 'Creating users defined in STATBUS_USERS_JSON=[{"email":"john@doe.com","password":"secret"}, ...]'

# Parse the JSON array and iterate over each object
echo "${STATBUS_USERS_JSON}" | jq -c '.[]' | while read -r user; do
  # Extract user details using jq
  email=$(echo "${user}" | jq -r '.email')
  password=$(echo "${user}" | jq -r '.password')

  # Use the official API, since there isn't an SQL route for this! :-(
  # Run the curl command for each user
  curl "http://$SUPABASE_BIND_ADDRESS/auth/v1/admin/users" \
    -H 'accept: application/json' \
    -H "apikey: $SERVICE_ROLE_KEY" \
    -H "authorization: Bearer $SERVICE_ROLE_KEY" \
    -H 'content-type: application/json' \
    --data-raw "{\"email\":\"$email\", \"password\":\"$password\", \"email_confirm\":true}"
done

eval $(./devops/manage-statbus.sh postgres-variables)
PGUSER=supabase_admin psql -c 'create extension sql_saga cascade;'
PGUSER=postgres psql < dbseed/create-db-structure.sql
