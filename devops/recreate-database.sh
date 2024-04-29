#!/bin/bash
# devops/recreate-database.sh
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

./devops/manage-statbus.sh create-users
./devops/manage-statbus.sh activate_sql_saga

./devops/manage-statbus.sh create-db-structure
