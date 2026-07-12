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
PG_PARAMS="$PG_PARAMS -c shared_buffers=${DB_SHARED_BUFFERS:-2GB}"
PG_PARAMS="$PG_PARAMS -c maintenance_work_mem=${DB_MAINTENANCE_WORK_MEM:-1GB}"
PG_PARAMS="$PG_PARAMS -c effective_cache_size=${DB_EFFECTIVE_CACHE_SIZE:-6GB}"
PG_PARAMS="$PG_PARAMS -c work_mem=${DB_WORK_MEM:-256MB}"
# temp_buffers must be set at server startup; cannot be changed after temp tables are accessed
PG_PARAMS="$PG_PARAMS -c temp_buffers=${DB_TEMP_BUFFERS:-1GB}"
# wal_buffers controls WAL write buffering; larger values reduce disk I/O
PG_PARAMS="$PG_PARAMS -c wal_buffers=${DB_WAL_BUFFERS:-122MB}"
# max_connections: STATBUS needs ~25 peak (worker + PostgREST + admin)
PG_PARAMS="$PG_PARAMS -c max_connections=${DB_MAX_CONNECTIONS:-30}"
# WAL sizing: large imports generate massive WAL; scale with memory
PG_PARAMS="$PG_PARAMS -c max_wal_size=${DB_MAX_WAL_SIZE:-4GB}"
PG_PARAMS="$PG_PARAMS -c min_wal_size=${DB_MIN_WAL_SIZE:-1GB}"
# WAL compression: reduces I/O volume ~50% at low CPU cost
PG_PARAMS="$PG_PARAMS -c wal_compression=lz4"

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

# STATBUS-161: INIT-INCOMPLETE SENTINEL check — intercept the postgres image's
# "Skipping initialization" path BEFORE we exec the official entrypoint below.
#
# WHY HERE: this wrapper is the container entrypoint (postgres/docker-compose.yml
# entrypoint override) and runs on EVERY boot; the official docker-entrypoint.sh
# we exec at the end owns the initdb-vs-"Skipping initialization" decision (it
# inits only an empty PGDATA). init-db.sh writes .statbus-init-incomplete as its
# first act and removes it as its last, so its PRESENCE means a prior init never
# finished. Under `restart: unless-stopped` (postgres/docker-compose.yml) an
# aborted init-db exits the container, docker restarts it, and the official
# entrypoint would otherwise see a non-empty PGDATA and report the half-built
# cluster HEALTHY ("Skipping initialization") — the exact STATBUS-151 mechanism (a
# [1/8] validation refuse became a baffling downstream pg_restore role error).
# Wiping PGDATA here forces a clean re-init, re-hitting the original failure
# LOUDLY every boot until the cause is fixed, then succeeding on the first boot
# after (init doing its job on an empty volume — NOT a standing self-heal).
#
# SAFETY (STATBUS-161 AC#3, by construction): the wipe fires ONLY when the sentinel
# is present AND PGDATA is a non-empty path. The sentinel exists only in clusters
# init-db.sh created and never finished — a completed init removed it, and a PGDATA
# created any other way (plain postgres, a restored volume) never had it — so a
# healthy cluster is UNWIPEABLE. A hand-planted sentinel is deliberate intent
# (no-wrong-without-intent).
#
# BOUNDARY (named, not covered — by design): a kill during initdb ITSELF, before
# the initdb.d hooks (thus before init-db.sh writes the sentinel), leaves a partial
# PGDATA with NO sentinel. That is NOT the silent-healthy class this guards — an
# incomplete initdb cluster fails postgres startup LOUDLY rather than reporting
# healthy — so it needs no sentinel.
STATBUS_PGDATA="${PGDATA:-/var/lib/postgresql/data}"
if [ -n "$STATBUS_PGDATA" ] && [ -f "$STATBUS_PGDATA/.statbus-init-incomplete" ]; then
    echo "FATAL-RECOVERY: a previous database initialization NEVER COMPLETED (sentinel $STATBUS_PGDATA/.statbus-init-incomplete present)." >&2
    echo "  A half-initialized cluster would otherwise boot 'healthy' but be missing roles/schema (STATBUS-151)." >&2
    echo "  Wiping the partial PGDATA and re-running initialization from scratch — the original failure repeats loudly until its cause is fixed." >&2
    find "$STATBUS_PGDATA" -mindepth 1 -delete
fi

echo "Handing off to /usr/local/bin/docker-entrypoint.sh postgres $PG_PARAMS"
# The `docker-entrypoint.sh` script (from the base PostgreSQL image)
# will handle PGDATA initialization, chown/chmod, and then
# exec gosu postgres postgres $PG_PARAMS
exec /usr/local/bin/docker-entrypoint.sh postgres $PG_PARAMS
