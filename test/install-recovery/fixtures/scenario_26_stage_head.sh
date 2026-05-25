#!/bin/bash
# Harness fixture for scenario 26 (archivebackup-watchdog).
# Stages HEAD on the VM: ensures the commit SHA is present in the git repo,
# then checks it out.
#
# Usage (on the VM, as statbus):
#   bash /tmp/scenario_26_stage_head.sh <HEAD_SHA>
#
# Delivered via scp — not via heredoc-over-ssh — so newlines survive the
# transport boundary.  Follows the CLAUDE.md no-heredoc-over-ssh rule.
set -euo pipefail
HEAD_SHA="${1:?HEAD_SHA required as first argument}"
cd ~/statbus
if ! git cat-file -e "$HEAD_SHA" 2>/dev/null; then
    git fetch --depth 1 origin "$HEAD_SHA" || { echo "FATAL: HEAD not on origin" >&2; exit 1; }
fi
git checkout "$HEAD_SHA"
