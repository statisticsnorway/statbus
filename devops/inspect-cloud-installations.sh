#!/bin/bash
# devops/devops.sh
set -euo pipefail

if test -n "${DEBUG:-}"; then
  set -x
fi

if ! command -v choose &> /dev/null; then
  echo "Error: The 'choose' command is not available. Please install it, e.g. with:" >&2
  echo "  brew install choose-rust" >&2
  exit 1
fi

# Get all branches matching the pattern devops/deploy-to-(.*) except production
SUFFIXES=$(git branch -a | grep 'remotes/origin/devops/deploy-to-' | grep -v 'production' | sd 'remotes/origin/devops/deploy-to-(.*?)' '$1')

# Function to extract information from environment files
extract_info() {
  local user=$1
  ssh "$user@niue.statbus.org" bash <<'EOF'
set -euo pipefail
export $(egrep -v '^#' ~/statbus/.env | xargs)
statbus_users=$(yq '.[] | "  " + .email + " " + (.role // "admin_user") + " " + .password' ~/statbus/.users.yml)
cat <<EOS
############################################################
## ${STATBUS_URL} - ${NEXT_PUBLIC_DEPLOYMENT_SLOT_CODE} - ${NEXT_PUBLIC_DEPLOYMENT_SLOT_NAME}
############################################################
Frontend: ${STATBUS_URL}/
Username Role Password:
${statbus_users}
############################################################
PostgreSQL: postgresql://postgres:${POSTGRES_ADMIN_PASSWORD}@localhost:${CADDY_DB_PORT}/${POSTGRES_APP_DB}
Port: ${CADDY_DB_PORT}
Database: ${POSTGRES_APP_DB}
User: ${POSTGRES_APP_USER}
Password: ${POSTGRES_APP_PASSWORD}
############################################################
Shell Access: 'ssh ${USER}@niue.statbus.org'
############################################################

EOS
EOF
}

# Iterate over each deployment slot
for SUFFIX in $SUFFIXES; do
  # Derive the user from the branch name
  user="statbus_${SUFFIX}"
  extract_info "$user"
done
