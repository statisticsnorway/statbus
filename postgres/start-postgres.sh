#!/bin/sh
set -e

# Arguments for the postgres command, not including "postgres" itself.
# These will be passed to the original docker-entrypoint.sh.
PG_PARAMS=""

# Core configuration parameters that should always be set via command line
# to ensure they are applied regardless of postgresql.conf content.
PG_PARAMS="$PG_PARAMS -c config_file=/etc/postgresql/postgresql.conf" # Ensure our config file is loaded.
# The following logging settings are crucial for Docker integration and override postgresql.conf
PG_PARAMS="$PG_PARAMS -c logging_collector=off"
PG_PARAMS="$PG_PARAMS -c log_destination=stderr"

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

echo "Handing off to /usr/local/bin/docker-entrypoint.sh postgres $PG_PARAMS"
# The `docker-entrypoint.sh` script (from the base PostgreSQL image)
# will handle PGDATA initialization, chown/chmod, and then
# exec gosu postgres postgres $PG_PARAMS
exec /usr/local/bin/docker-entrypoint.sh postgres $PG_PARAMS
