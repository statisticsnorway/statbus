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
-- Add extension for simple text search.
CREATE EXTENSION "pg_trgm";
-- CREATE EXTENSION "btree_gist";
UPDATE pg_database SET datistemplate='true' WHERE datname='template_statbus';
EOF

sql_password=$(cat /run/secrets/db-admin-password)

psql -c "CREATE USER statbus_development WITH PASSWORD '$sql_password' CREATEDB;"
psql -c "CREATE DATABASE statbus_development WITH template template_statbus OWNER statbus_development;"

psql -c "CREATE USER statbus_test WITH PASSWORD '$sql_password' CREATEDB;"
psql -c "CREATE DATABASE statbus_test WITH template template_statbus OWNER statbus_test;"

