#!/bin/bash
# devops/devops.sh
set -euo pipefail

if test -n "${DEBUG:-}"; then
  set -x
fi

# TODO: if the `choose` command is not available suggest installation with `brew install choose-rust`

# Get all branches matching the pattern devops/deploy-to-(.*) except production
SUFFIXES=$(git branch -a | grep 'remotes/origin/devops/deploy-to-' | grep -v 'production' | sd 'remotes/origin/devops/deploy-to-(.*?)' '$1')

# Function to extract information from environment files
extract_info() {
  local user=$1
  ssh "$user@niue.statbus.org" bash <<'EOF'
set -euo pipefail
export $(egrep -v '^#' ~/statbus/.env | xargs)
statbus_users=$(yq '.[] | "  " + .email + " " + (.role // "super_user") + " " + .password' ~/statbus/.users.yml)
cat <<EOS
############################################################
## ${STATBUS_URL} - ${NEXT_PUBLIC_DEPLOYMENT_SLOT_CODE} - ${NEXT_PUBLIC_DEPLOYMENT_SLOT_NAME}
############################################################
Frontend: ${STATBUS_URL}/
Username Role Password:
${statbus_users}
############################################################
API: ${NEXT_PUBLIC_BROWSER_API_URL}
API Username ${DASHBOARD_USERNAME}
API Password ${DASHBOARD_PASSWORD}
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
