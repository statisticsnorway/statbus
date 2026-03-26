#!/bin/bash
# Deploy StatBus by telling the upgrade daemon to discover new releases.
#
# The daemon handles: poll GitHub, pull images, backup, checkout, migrate, restart.
# This script just sends NOTIFY upgrade_check via the CLI.
#
# Called by:
#   - notify-all-clouds.yaml (on master push, all servers)
#   - Manual: ssh statbus_<code>@niue "cd statbus && ./devops/deploy.sh"
#
# Requires ./sb binary. Fails cleanly if not installed (server needs bootstrap).
set -euo pipefail
cd "${HOME}/statbus"
./sb upgrade discover
