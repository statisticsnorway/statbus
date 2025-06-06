#!/bin/bash
# ./statbus/devops/deploy-statbus.sh
#
set -euo pipefail # Exit on error, unbound variable, or any failure in a pipeline

if test -n "${DEBUG:-}"; then
  set -x # Print all commands before running them - for easy debugging.
fi

sub_domain=$(echo "$USER" | awk -F'_' '{print ($2 == "" ? $1 : $2)}')
fqdn=$(hostname --fqdn)

cd $HOME

touch "$HOME/maintenance"
# Set a trap to remove the file on exit or on receiving a signal
trap 'rm -f "$HOME/maintenance"' EXIT

pushd statbus
git fetch

# Determine the current branch
current_branch=$(git rev-parse --abbrev-ref HEAD)
target_branch="devops/deploy-to-${sub_domain}"

# If not on the desired branch, checkout or reset it to match remote
if [ "$current_branch" != "$target_branch" ]; then
  # Check if the branch exists locally
  if git show-ref --quiet refs/heads/"$target_branch"; then
    # Branch exists locally, so checkout
    git checkout "$target_branch"
  else
    # Branch does not exist locally, checkout as new branch and set to track remote
    git checkout -b "$target_branch" --track origin/"$target_branch"
  fi
fi

# Mark the current position before the update
commit_before=$(git rev-parse HEAD)

# Reset the local branch to exactly match the remote branch, discarding any local diverged commits
git reset --hard origin/"$target_branch"

commit_after=$(git rev-parse HEAD)
common_ancestor=$(git merge-base "$commit_before" "$commit_after")

if [ "$commit_before" != "$commit_after" ]; then
  commit_messages=$(git log --oneline --reverse "$common_ancestor..$commit_after")
else
  # No new commits, so repeat the last commit message.
  commit_messages=$(git log -1 --oneline)
fi

echo "Stopping the application"
./devops/manage-statbus.sh stop app || { echo "Failed to stop the application"; exit 1; }

dbseed_changes=$(git diff --name-only "$commit_before" "$commit_after" | grep "^dbseed/"; true)
# Check for modified migrations (M), ignoring added ones (A)
migrations_changes=$(git diff --name-status "$commit_before" "$commit_after" | grep "^M.*migrations/" | cut -f2-; true)
if test -n "$dbseed_changes" || test -n "$migrations_changes" || test -n "${RECREATE:-}"; then
  if test -n "$dbseed_changes"; then
    echo "Changes detected in dbseed/, recreating the backend with the latest database structures"
  elif test -n "$migrations_changes"; then
    echo "Changes detected in existing migrations/, recreating the backend with the latest database structures"
  else
    echo "env RECREATE is set, recreating the backend with the latest database structures"
  fi

  if pgrep -u ${USER} --exact statbus; then
    echo "Stopping background loading"
    pkill -u ${USER} --exact statbus
  else
    echo "No background statbus process found."
  fi

  pushd cli
  source /etc/profile.d/homebrew.sh
  shards build
  popd

  ./devops/manage-statbus.sh stop all
  ./devops/manage-statbus.sh delete-db

  ./devops/manage-statbus.sh generate-config

  ./devops/manage-statbus.sh start all

  # Copy static files out for Caddy to serve
  mkdir -p ${HOME}/public
  rm -rf ${HOME}/public/*
  docker compose cp app:/app/public/ ${HOME}/public/

  ./devops/manage-statbus.sh activate_sql_saga
  ./devops/manage-statbus.sh create-db-structure
  ./devops/manage-statbus.sh create-users

  if test -f ${HOME}/statbus/tmp/enheter.csv; then
    ./devops/manage-statbus.sh psql < ./samples/norway/setup.sql

    SESSION_NAME="statbus_import"
    if tmux has-session -t "$SESSION_NAME" 2>/dev/null; then
      echo "Stopping old tmux session '$SESSION_NAME'"
      tmux kill-session -t "$SESSION_NAME"
    fi

    tmux new-session -d -s "$SESSION_NAME"
    echo "Running the import command in tmux session '$SESSION_NAME'..."
    tmux send-keys -t "$SESSION_NAME" "cd $(pwd) && ../samples/norway/brreg/brreg-import-selection.sh && ../samples/norway/brreg-import-downloads-from-tmp.sh" C-m
    popd
  fi
else
  echo "No changes in dbseed/, starting again"
  echo "Building and starting the frontend"
  ./devops/manage-statbus.sh start required || { echo "Failed to start the app"; exit 1; }
fi

# Ensure the .env file exists and load the Slack token
if [ ! -f .env ]; then
  echo ".env file not found, aborting."
  exit 1
fi

SLACK_TOKEN=$(./devops/dotenv --file .env get SLACK_TOKEN)
STATBUS_URL=$(./devops/dotenv --file .env get STATBUS_URL)

# Send a notification to Slack
cat <<EOF | curl --data @- -H "Content-type: application/json; charset=utf-8" -H "Authorization: Bearer $SLACK_TOKEN" -X POST https://slack.com/api/chat.postMessage || { echo "Failed to send Slack notification"; exit 1; }
{
  "channel": "statbus-utvikling",
  "blocks": [
    {
      "type": "section",
      "text": {
        "type": "mrkdwn",
        "text": "Push-et endringer fra <https://github.com/statisticsnorway/statbus|github> til <${STATBUS_URL}|${sub_domain}>"
      }
    },
    {
      "type": "divider"
    },
    {
      "type": "rich_text",
      "elements": [
        {
          "type": "rich_text_preformatted",
          "elements": [
            {
              "type": "text",
              "text": "$commit_messages"
            }
          ]
        }
      ]
    },
    {
      "type": "divider"
    },
    {
      "type": "context",
      "elements": [
        {
          "type": "plain_text",
          "text": "Hilsen ${USER}@${fqdn}",
          "emoji": true
        }
      ]
    }
  ]
}
EOF
