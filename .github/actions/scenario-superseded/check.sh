#!/usr/bin/env bash
set -euo pipefail

# Every matrix job leaves one evidence file, including a manual branch run.
# Its filename is the matrix slug, so the aggregate can count all jobs without
# relying on GitHub's last-writer-wins matrix job outputs.
marker="${RUNNER_TEMP}/scenario-freshness/${SCENARIO}.txt"
mkdir -p "$(dirname "$marker")"
echo "marker=$marker" >> "$GITHUB_OUTPUT"
echo 'superseded=false' > "$marker"
if [[ ! ${CANDIDATE_REF:-} =~ ^v[0-9]+\.[0-9]+\.[0-9]+-rc\.[0-9]+$ ]]; then
  echo "${CANDIDATE_REF:-<unknown>} is not an RC candidate; proceeding."
  echo 'superseded=false' >> "$GITHUB_OUTPUT"
  exit 0
fi

# Query origin now; the checkout's tags may predate this queued matrix job.
# Do not fail or stop a legitimate scenario on an unknown remote response.
if ! tags="$(git ls-remote --tags --refs origin 'v*-rc.*')"; then
  echo '::warning title=RC freshness unknown::remote lookup failed; proceeding'
  echo 'superseded=false' >> "$GITHUB_OUTPUT"
  exit 0
fi
newest="$(printf '%s\n' "$tags" | awk '$2 ~ /^refs\/tags\/v[0-9]+\.[0-9]+\.[0-9]+-rc\.[0-9]+$/ {sub(/^refs\/tags\//, "", $2); print $2}' | LC_ALL=C sort -V | tail -n 1)"
if [ -z "$newest" ]; then
  echo '::warning title=RC freshness unknown::no RC tags returned; proceeding'
  echo 'superseded=false' >> "$GITHUB_OUTPUT"
  exit 0
fi
if [ "$newest" != "$CANDIDATE_REF" ] && [ "$(printf '%s\n%s\n' "$CANDIDATE_REF" "$newest" | LC_ALL=C sort -V | tail -n 1)" = "$newest" ]; then
  echo "SUPERSEDED by $newest: stopping before VM boot"
  echo 'superseded=true' >> "$GITHUB_OUTPUT"
  echo 'superseded=true' > "$marker"
  echo "- **$SCENARIO**: SUPERSEDED by \`$newest\`: stopping before VM boot; no VM created." >> "$GITHUB_STEP_SUMMARY"
else
  echo "$CANDIDATE_REF is still the newest RC; proceeding."
  echo 'superseded=false' >> "$GITHUB_OUTPUT"
fi
