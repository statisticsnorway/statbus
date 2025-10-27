#!/bin/sh
set -e

# Generate pg_hba.conf from template to inject the correct OAuth issuer URL.
# The output is written to the standard location, which is then picked up by PostgreSQL.
envsubst '${OAUTH_ISSUER_URL}' < /etc/postgresql/pg_hba.conf.template > /etc/postgresql/pg_hba.conf

# Arguments for the postgres command, not including "postgres" itself.
# These will be passed to the original docker-entrypoint.sh.
PG_PARAMS=""

# Core configuration parameters that should always be set via command line
# to ensure they are applied regardless of postgresql.conf content.
PG_PARAMS="$PG_PARAMS -c config_file=/etc/postgresql/postgresql.conf" # Ensure our config file is loaded.
# The following logging settings are crucial for Docker integration and override postgresql.conf
PG_PARAMS="$PG_PARAMS -c logging_collector=off"
PG_PARAMS="$PG_PARAMS -c log_destination=stderr"

# Configure the JWT secret for oAuth JWT validation.
PG_PARAMS="$PG_PARAMS -c pg_jwt_validator.secret=${JWT_SECRET}"

# Dynamic memory configuration (overrides postgresql.conf)
# These can be set in the .env file. See tmp/db-memory-todo.md for tuning guidance.
PG_PARAMS="$PG_PARAMS -c shared_buffers=${DB_SHARED_BUFFERS:-1GB}"
PG_PARAMS="$PG_PARAMS -c maintenance_work_mem=${DB_MAINTENANCE_WORK_MEM:-1GB}"
PG_PARAMS="$PG_PARAMS -c effective_cache_size=${DB_EFFECTIVE_CACHE_SIZE:-3GB}"
PG_PARAMS="$PG_PARAMS -c work_mem=${DB_WORK_MEM:-100MB}"

# Default logging levels (these match postgresql.conf but will be overridden if DEBUG=true)
# These values are set here to be passed as command-line arguments,
# which take precedence over postgresql.conf settings.
LOG_MIN_MESSAGES="fatal" # Default, matches postgresql.conf
LOG_MIN_DURATION_STATEMENT="1000" # Default, matches postgresql.conf

# Check DEBUG environment variable (default to false if not set)
if [ "${DEBUG:-false}" = "true" ]; then
  echo "DEBUG mode is true. Adjusting PostgreSQL log levels to INFO and 0ms."
  LOG_MIN_MESSAGES="INFO"
  LOG_MIN_DURATION_STATEMENT="0"
fi

PG_PARAMS="$PG_PARAMS -c log_min_messages=${LOG_MIN_MESSAGES}"
PG_PARAMS="$PG_PARAMS -c log_min_duration_statement=${LOG_MIN_DURATION_STATEMENT}"

# Since Caddy terminates SSL postgres must not, since it doesn't have the right certificate.
export PGOAUTHDEBUG=UNSAFE

echo "Handing off to /usr/local/bin/docker-entrypoint.sh postgres $PG_PARAMS"
# The `docker-entrypoint.sh` script (from the base PostgreSQL image)
# will handle PGDATA initialization, chown/chmod, and then
# exec gosu postgres postgres $PG_PARAMS
exec /usr/local/bin/docker-entrypoint.sh postgres $PG_PARAMS
