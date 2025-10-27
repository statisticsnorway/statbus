#!/bin/bash
#
# End-to-end test script for the pg_jwt_validator OAuth extension.
#
# This script performs the following steps:
# 1. Rebuilds and restarts the PostgreSQL Docker container.
# 2. Generates a valid JWT using the `pgjwt` extension.
# 3. Attempts to connect to the database via psql using the generated JWT.
#
# Usage:
#   ./postgres/test-pg_jwt_validator.sh
#
# To run in debug mode (prints all commands):
#   DEBUG=true ./postgres/test-pg_jwt_validator.sh

set -euo pipefail

# Enable debug mode if DEBUG is set to true
if [[ "${DEBUG:-false}" == "true" ]]; then
  set -x
  export DEBUG
fi

log() {
  echo "==> $1"
}

# --- Main script ---

log "Starting OAuth connection test..."

if [ ! -f .env ]; then
  log "ERROR: .env file not found. Please run './devops/manage-statbus.sh generate-env' first."
  exit 1
fi

log "Rebuilding and restarting the database container..."
docker compose build db
docker compose up -d db --force-recreate

# Wait for DB to be healthy
log "Waiting for database to be ready..."
count=0
while ! docker compose exec -T db pg_isready -U postgres -h localhost > /dev/null 2>&1; do
  if [ $count -gt 20 ]; then
    log "ERROR: Database did not become ready in time."
    exit 1
  fi
  sleep 2
  count=$((count+1))
done
log "Database is ready."


log "Fetching connection details from .env file..."
DB_PUBLIC_LOCALHOST_PORT=$(grep DB_PUBLIC_LOCALHOST_PORT .env | cut -d '=' -f2)
JWT_SECRET=$(grep JWT_SECRET .env | cut -d '=' -f2)

if [ -z "$DB_PUBLIC_LOCALHOST_PORT" ] || [ -z "$JWT_SECRET" ]; then
    log "ERROR: DB_PUBLIC_LOCALHOST_PORT or JWT_SECRET not found in .env file."
    exit 1
fi

log "Generating a temporary JWT for authentication..."
SQL_QUERY="SELECT sign(json_build_object('sub', 'test_user', 'email', 'test@test.com', 'role', 'regular_user', 'iss', 'https://auth.statbus.org', 'aud', 'db:connect', 'exp', extract(epoch from now() + interval '1 hour')), '${JWT_SECRET}');"
STATBUS_TOKEN=$(echo "$SQL_QUERY" | ./devops/manage-statbus.sh psql -t -A)

if [ -z "$STATBUS_TOKEN" ]; then
    log "ERROR: Failed to generate STATBUS_TOKEN."
    exit 1
fi

log "Attempting to connect with psql using the JWT..."
if PGPASSWORD=$STATBUS_TOKEN psql "host=localhost port=${DB_PUBLIC_LOCALHOST_PORT} user=postgres dbname=postgres sslmode=require" -c "SELECT current_user;" | grep -q "postgres"; then
  log "SUCCESS: Connection successful! The pg_jwt_validator is working."
else
  log "ERROR: Connection failed. Check the PostgreSQL logs for details from the validator."
  exit 1
fi
