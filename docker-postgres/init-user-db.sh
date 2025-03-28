#!/bin/bash
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

ALTER DATABASE "template_statbus" SET datestyle TO 'ISO, DMY';
\c "template_statbus"

-- Add extensions
CREATE EXTENSION IF NOT EXISTS "pg_trgm";
CREATE EXTENSION IF NOT EXISTS "pg_cron";
CREATE EXTENSION IF NOT EXISTS "pgtap";
CREATE EXTENSION IF NOT EXISTS "plpgsql_check";
CREATE EXTENSION IF NOT EXISTS "pg_safeupdate";
CREATE EXTENSION IF NOT EXISTS "wal2json";
CREATE EXTENSION IF NOT EXISTS "pg_hashids";
CREATE EXTENSION IF NOT EXISTS "http";
CREATE EXTENSION IF NOT EXISTS "sql_saga";

UPDATE pg_database SET datistemplate='true' WHERE datname='template_statbus';
EOF

# Use environment variables if provided, otherwise use defaults
DB_NAME=${POSTGRES_DB:-statbus_development}
DB_USER=${POSTGRES_USER:-statbus_development}
DB_PASSWORD="${POSTGRES_PASSWORD:-postgres}"

# Create main database user and database
psql -c "CREATE USER \"$DB_USER\" WITH PASSWORD '$DB_PASSWORD' CREATEDB;"
psql -c "CREATE DATABASE \"$DB_NAME\" WITH template template_statbus OWNER \"$DB_USER\";"

# Always create test database for development purposes
psql -c "CREATE USER statbus_test WITH PASSWORD '$DB_PASSWORD' CREATEDB;"
psql -c "CREATE DATABASE statbus_test WITH template template_statbus OWNER statbus_test;"
