#!/bin/bash
#
set -e # Exit on any failure for any command

if test -n "$DEBUG"; then
  set -x # Print all commands before running them - for easy debugging.
fi

WORKSPACE="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && cd .. && pwd )"

cd $WORKSPACE

echo Recreate the backend with the lastest database structures
pushd supabase_docker
docker compose down
rm -rf ./volumes/db/data
docker compose up -d

echo Create users for the developers
# Use the official API, since there isn't an SQL route for this! :-(
source .env

echo "Wait for admin api (gotrue) to start"
starting=true
while $starting; do
	sleep 1
	curl "http://$SUPABASE_BIND_ADDRESS/auth/v1/health" \
	-H 'accept: application/json' \
	-H "apikey: $SERVICE_ROLE_KEY" && starting=false
done

curl "http://$SUPABASE_BIND_ADDRESS/auth/v1/admin/users" \
-H 'accept: application/json' \
-H "apikey: $SERVICE_ROLE_KEY" \
-H "authorization: Bearer $SERVICE_ROLE_KEY" \
-H 'content-type: application/json' \
--data-raw '{"email":"jorgen@veridit.no", "password":"thaik0VooD8p", "email_confirm": true}' 
curl "http://$SUPABASE_BIND_ADDRESS/auth/v1/admin/users" \
-H 'accept: application/json' \
-H "apikey: $SERVICE_ROLE_KEY" \
-H "authorization: Bearer $SERVICE_ROLE_KEY" \
-H 'content-type: application/json' \
--data-raw '{"email":"erik.soberg@ssb.no", "password":"Chei4Aijiexu", "email_confirm": true}' 
curl "http://$SUPABASE_BIND_ADDRESS/auth/v1/admin/users" \
-H 'accept: application/json' \
-H "apikey: $SERVICE_ROLE_KEY" \
-H "authorization: Bearer $SERVICE_ROLE_KEY" \
-H 'content-type: application/json' \
--data-raw '{"email":"jonas.lundeland@sonat.no", "password":"shaiShozoe9O", "email_confirm": true}' 

popd

PGHOST=localhost PGPORT=$DB_PUBLIC_LOCALHOST_PORT PGDATABASE=$POSTGRES_DB PGUSER=supabase_admin PGPASSWORD="$POSTGRES_PASSWORD" psql -c 'create extension sql_saga cascade;'
PGHOST=localhost PGPORT=$DB_PUBLIC_LOCALHOST_PORT PGDATABASE=$POSTGRES_DB PGUSER=postgres PGPASSWORD="$POSTGRES_PASSWORD" psql < dbseed/create-db-structure.sql
