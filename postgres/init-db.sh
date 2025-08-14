#!/bin/bash
# Unified initialization script for PostgreSQL database
# Exit on error, unbound variable, or any failure in a pipeline
set -euo pipefail

# Enable debug mode if DEBUG is set to true or 1
if [[ "${DEBUG:-}" == "true" || "${DEBUG:-}" == "1" ]]; then
  set -x  # Print all commands before running them
fi

# The postgres role already exists as the default superuser

echo "Creating template database with extensions..."

# Create and configure template database
psql <<'EOF'
CREATE DATABASE "template_statbus"
  ENCODING   'utf-8'
  -- Activate the chosen locale
  LC_COLLATE 'en_US.utf8'
  LC_CTYPE   'en_US.utf8'
  --LC_COLLATE 'nb_NO.utf8'
  --LC_CTYPE   'nb_NO.utf8'
  --LC_COLLATE 'ru_RU.utf8'
  --LC_CTYPE   'ru_RU.utf8'
  --LC_COLLATE 'ky_KG.utf8'
  --LC_CTYPE   'ky_KG.utf8'
  template = template0;

-- Set database-wide defaults
ALTER DATABASE "template_statbus" SET datestyle TO 'ISO, DMY';
ALTER DATABASE "template_statbus" SET client_encoding TO 'UTF8';
ALTER DATABASE "template_statbus" SET standard_conforming_strings TO on;
ALTER DATABASE "template_statbus" SET check_function_bodies TO true;
ALTER DATABASE "template_statbus" SET xmloption TO content;
ALTER DATABASE "template_statbus" SET client_min_messages TO warning;
ALTER DATABASE "template_statbus" SET row_security TO on;
\c "template_statbus"

-- Add basic extensions
CREATE EXTENSION IF NOT EXISTS "pg_trgm";
-- Disable pgtap since it adds a lot of functions to public, and we don't currently use ut in statbus.
--CREATE EXTENSION IF NOT EXISTS "pgtap";
CREATE EXTENSION IF NOT EXISTS "plpgsql_check";
CREATE EXTENSION IF NOT EXISTS "pgcrypto";
CREATE EXTENSION IF NOT EXISTS "pgjwt"; -- Depends on pgcrypto
CREATE EXTENSION IF NOT EXISTS "pg_hashids";
CREATE EXTENSION IF NOT EXISTS "btree_gist";
CREATE EXTENSION IF NOT EXISTS "http";
CREATE EXTENSION IF NOT EXISTS "sql_saga";
CREATE EXTENSION IF NOT EXISTS "hypopg";
CREATE EXTENSION IF NOT EXISTS "index_advisor";
CREATE EXTENSION IF NOT EXISTS "pg_stat_statements";  -- Load before pg_stat_monitor according to doc.
CREATE EXTENSION IF NOT EXISTS "pg_stat_monitor";
CREATE EXTENSION IF NOT EXISTS "pg_graphql";
-- The extension pg_safeupdate is installed for the roles that PostgREST
-- uses only, to prevent DELETE without a WHERE via API in a migration with:
-- ALTER ROLE authenticator SET session_preload_libraries = safeupdate;

UPDATE pg_database SET datistemplate='true' WHERE datname='template_statbus';
EOF

# Use environment variables from .env (or Dockerfile defaults if not set)
echo "Using database configuration:"
echo "  App DB: $POSTGRES_APP_DB"
echo "  App User: $POSTGRES_APP_USER"

echo "Creating deployment-specific database user and database..."
# Create deployment-specific database user and database
psql -c "CREATE USER \"$POSTGRES_APP_USER\" WITH PASSWORD '$POSTGRES_APP_PASSWORD' CREATEDB;"
psql -c "CREATE DATABASE \"$POSTGRES_APP_DB\" WITH template template_statbus OWNER \"$POSTGRES_APP_USER\";"

echo "Setting up authentication roles..."
# Create authenticator role for PostgREST
psql -d "$POSTGRES_APP_DB" -c "CREATE ROLE authenticator NOINHERIT NOCREATEDB NOCREATEROLE NOSUPERUSER LOGIN PASSWORD '$POSTGRES_AUTHENTICATOR_PASSWORD';"

# Create anon and authenticated roles
psql -d "$POSTGRES_APP_DB" -c "CREATE ROLE anon NOLOGIN NOINHERIT NOCREATEDB NOCREATEROLE NOSUPERUSER;"
psql -d "$POSTGRES_APP_DB" -c "CREATE ROLE authenticated NOLOGIN NOINHERIT NOCREATEDB NOCREATEROLE NOSUPERUSER;"

# Grant roles to authenticator
psql -d "$POSTGRES_APP_DB" -c "GRANT anon TO authenticator;"
psql -d "$POSTGRES_APP_DB" -c "GRANT authenticated TO authenticator;"

# Create auth schema (tables will be created by migrations)
psql -d "$POSTGRES_APP_DB" -c "CREATE SCHEMA IF NOT EXISTS auth;"

# Grant basic permissions
psql -d "$POSTGRES_APP_DB" <<'EOF'
-- Grant usage on auth schema
GRANT USAGE ON SCHEMA auth TO authenticated;
GRANT USAGE ON SCHEMA auth TO anon;
EOF

echo "Setting up notify reader role and user..."
psql -d "$POSTGRES_APP_DB" <<EOSQL
-- Create a role for read-only access for the notification listener
CREATE ROLE notify_reader;

-- Grant connect to the database
GRANT CONNECT ON DATABASE "$POSTGRES_APP_DB" TO notify_reader;

-- Grant usage on the public schema. Table permissions will be granted in migrations.
GRANT USAGE ON SCHEMA public TO notify_reader;

-- Create the user and grant the role
CREATE USER "$POSTGRES_NOTIFY_USER" WITH PASSWORD '$POSTGRES_NOTIFY_PASSWORD';
GRANT notify_reader TO "$POSTGRES_NOTIFY_USER";
EOSQL

echo "Database initialization completed successfully."
