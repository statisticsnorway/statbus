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

# Dynamic memory configuration (overrides postgresql.conf)
# All memory settings are derived from DB_MEM_LIMIT in .env.config (single source of truth).
# These are calculated by the CLI and passed via environment variables.
# See tmp/db-memory-todo.md for tuning rationale.
PG_PARAMS="$PG_PARAMS -c shared_buffers=${DB_SHARED_BUFFERS:-1GB}"
PG_PARAMS="$PG_PARAMS -c maintenance_work_mem=${DB_MAINTENANCE_WORK_MEM:-1GB}"
PG_PARAMS="$PG_PARAMS -c effective_cache_size=${DB_EFFECTIVE_CACHE_SIZE:-3GB}"
PG_PARAMS="$PG_PARAMS -c work_mem=${DB_WORK_MEM:-40MB}"
# temp_buffers must be set at server startup; cannot be changed after temp tables are accessed
PG_PARAMS="$PG_PARAMS -c temp_buffers=${DB_TEMP_BUFFERS:-512MB}"
# wal_buffers controls WAL write buffering; larger values reduce disk I/O
PG_PARAMS="$PG_PARAMS -c wal_buffers=${DB_WAL_BUFFERS:-64MB}"

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
  
  # Enable auto_explain for detailed query plan analysis in debug mode
  echo "DEBUG mode: Enabling auto_explain for import performance debugging."
  PG_PARAMS="$PG_PARAMS -c session_preload_libraries=auto_explain"
  PG_PARAMS="$PG_PARAMS -c auto_explain.log_min_duration=100"      # Log plans for queries > 100ms
  PG_PARAMS="$PG_PARAMS -c auto_explain.log_analyze=true"          # Include actual timings and row counts
  PG_PARAMS="$PG_PARAMS -c auto_explain.log_buffers=true"          # Include buffer usage statistics
  PG_PARAMS="$PG_PARAMS -c auto_explain.log_nested_statements=true" # Capture queries inside functions/procedures
  PG_PARAMS="$PG_PARAMS -c auto_explain.log_format=text"           # Use text format for better readability
fi

PG_PARAMS="$PG_PARAMS -c log_min_messages=${LOG_MIN_MESSAGES}"
PG_PARAMS="$PG_PARAMS -c log_min_duration_statement=${LOG_MIN_DURATION_STATEMENT}"

echo "Handing off to /usr/local/bin/docker-entrypoint.sh postgres $PG_PARAMS"
# The `docker-entrypoint.sh` script (from the base PostgreSQL image)
# will handle PGDATA initialization, chown/chmod, and then
# exec gosu postgres postgres $PG_PARAMS
exec /usr/local/bin/docker-entrypoint.sh postgres $PG_PARAMS
