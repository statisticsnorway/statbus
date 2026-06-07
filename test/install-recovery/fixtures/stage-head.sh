#!/bin/bash
# Harness fixture: stage HEAD on the VM (shared by the postswap archivebackup + resume-died scenarios).
# Stages HEAD on the VM: ensures the commit SHA is present in the git repo,
# checks it out, then pre-tags Docker images so that docker compose pull
# can fall back to local images when the harness commit has no registry entry.
#
# Usage (on the VM, as statbus):
#   bash /tmp/stage-head.sh <HEAD_SHA>
#
# Delivered via scp — not via heredoc-over-ssh — so newlines survive the
# transport boundary.  Follows the CLAUDE.md no-heredoc-over-ssh rule.
#
# Docker pull fall-back rationale:
#   applyPostSwap calls `docker compose pull` after `./sb config generate`.
#   config generate sets COMMIT_SHORT = git rev-parse --short=8 HEAD = the
#   harness commit's 8-char prefix.  CI only builds images for tagged commits;
#   the harness commit has no registry entry, so docker compose pull would
#   normally fail with "manifest not found".
#
#   Docker Compose v2 behaviour: if the registry returns an error (including
#   404) but the image exists locally under the requested tag, Compose uses
#   the local image and continues without error.  Pre-tagging the installed
#   release's images with the harness COMMIT_SHORT satisfies this: the pull
#   "fails" from the registry perspective but Compose falls back to local,
#   and the upgrade proceeds to the archiveBackup step where the inject site
#   fires.
set -euo pipefail
HEAD_SHA="${1:?HEAD_SHA required as first argument}"
cd ~/statbus

# Step 1: Capture the INSTALLED COMMIT_SHORT before git checkout changes HEAD.
# This is the tag under which the four COMMIT_SHORT images were pulled from
# the registry when the release was installed.
OLD_COMMIT_SHORT=$(./sb dotenv -f .env get COMMIT_SHORT 2>/dev/null || true)
OLD_COMMIT_SHORT=$(echo "$OLD_COMMIT_SHORT" | tr -d ' \r\n')

if ! git cat-file -e "$HEAD_SHA" 2>/dev/null; then
    git fetch --depth 1 origin "$HEAD_SHA" || { echo "FATAL: HEAD not on origin" >&2; exit 1; }
fi
git checkout "$HEAD_SHA"

# Step 2: Compute the NEW COMMIT_SHORT that config generate will produce.
NEW_COMMIT_SHORT=$(git rev-parse --short=8 HEAD)

# Step 3: Pre-tag images so docker compose pull can fall back to local.
# Only needed when the SHAs differ (always true for harness → HEAD transitions).
if [ -n "$OLD_COMMIT_SHORT" ] && [ "$OLD_COMMIT_SHORT" != "$NEW_COMMIT_SHORT" ]; then
    echo "  [stage] pre-tagging COMMIT_SHORT images: $OLD_COMMIT_SHORT → $NEW_COMMIT_SHORT"
    for img in statbus-app statbus-worker statbus-db statbus-proxy; do
        old_tag="ghcr.io/statisticsnorway/$img:$OLD_COMMIT_SHORT"
        new_tag="ghcr.io/statisticsnorway/$img:$NEW_COMMIT_SHORT"
        if docker image inspect "$old_tag" >/dev/null 2>&1; then
            docker tag "$old_tag" "$new_tag"
            echo "    ✓ $img:$OLD_COMMIT_SHORT → $img:$NEW_COMMIT_SHORT"
        else
            echo "    skip $img (not present locally as $old_tag)"
        fi
    done
else
    echo "  [stage] COMMIT_SHORT unchanged ($NEW_COMMIT_SHORT) — no image retagging needed"
fi
