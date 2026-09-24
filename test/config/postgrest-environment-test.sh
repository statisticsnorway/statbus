#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/../.."
grep -Fq 'PGRST_APP_SETTINGS_DEPLOYMENT_SLOT_CODE: ${DEPLOYMENT_SLOT_CODE:?' docker-compose.rest.yml
grep -Eq '^      PGRST_DB_CONFIG: "(true|false)"$' docker-compose.rest.yml
! grep -Eq '^      PGRST_DB_CONFIG: app\.' docker-compose.rest.yml
echo 'PASS: PostgREST receives selected slot via app settings and boolean DB config'
