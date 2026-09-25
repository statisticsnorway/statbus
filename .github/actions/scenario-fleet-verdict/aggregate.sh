#!/usr/bin/env bash
set -euo pipefail

scenarios=()
while IFS= read -r scenario; do
  scenarios+=("$scenario")
done < <(jq -er '.[] | if type == "string" then . else .scenario end' <<< "$MATRIX_JSON")
if [ "${#scenarios[@]}" -eq 0 ]; then
  echo '::error::No selected scenarios to aggregate' >&2
  exit 1
fi
actual="$(find "$MARKER_DIR" -type f -name '*.txt' | wc -l | tr -d ' ')"
if [ "$actual" -ne "${#scenarios[@]}" ]; then
  echo "::error::Expected ${#scenarios[@]} scenario freshness markers, found $actual; refusing to claim full coverage" >&2
  exit 1
fi
superseded=false
for scenario in "${scenarios[@]}"; do
  marker="$MARKER_DIR/$scenario.txt"
  if [ ! -f "$marker" ]; then
    echo "::error::Missing freshness marker for $scenario" >&2
    exit 1
  fi
  case "$(cat "$marker")" in
    superseded=true) superseded=true ;;
    superseded=false) ;;
    *) echo "::error::Invalid freshness marker for $scenario" >&2; exit 1 ;;
  esac
done

echo "superseded=$superseded" >> "$GITHUB_OUTPUT"
verdict_file="$RUNNER_TEMP/fleet-verdict.txt"
if [ "$superseded" = true ]; then
  echo 'SUPERSEDED' > "$verdict_file"
  echo '### SUPERSEDED: at least one scenario stopped before VM boot' >> "$GITHUB_STEP_SUMMARY"
else
  echo 'COMPLETE' > "$verdict_file"
fi
echo "verdict-file=$verdict_file" >> "$GITHUB_OUTPUT"
