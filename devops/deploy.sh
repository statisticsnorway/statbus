#!/bin/bash
# Deploy StatBus by notifying the upgrade daemon.
#
# The daemon handles: backup, checkout, pull, migrate, restart, health check.
# This script just tells it to check for new releases.
#
set -euo pipefail

if [ "${DEBUG:-}" = "true" ] || [ "${DEBUG:-}" = "1" ]; then
  set -x
fi

cd "${HOME}/statbus"

echo "Sending NOTIFY upgrade_check to upgrade daemon..."
echo "NOTIFY upgrade_check;" | ./sb psql

echo "Done. The upgrade daemon will discover and apply new releases."
