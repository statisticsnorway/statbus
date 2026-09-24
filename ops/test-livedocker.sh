#!/usr/bin/env bash
# Only this explicit livedb sub-tier authorizes real Docker in Go test binaries.
set -euo pipefail
workspace="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
dir="$(mktemp -d "${TMPDIR:-/tmp}/statbus-livedocker-XXXXXX")"
export COMPOSE_PROJECT_NAME="statbus-livedocker-$(basename "$dir" | tr '[:upper:]' '[:lower:]')"
export COMPOSE_FILE="$dir/compose.yaml"
export STATBUS_LIVEDOCKER_PROJECT_DIR="$dir"
printf '%s\n' "$COMPOSE_PROJECT_NAME" > "$dir/.statbus-livedocker"
cat > "$COMPOSE_FILE" <<'YAML'
services:
  fixture:
    image: alpine:latest
    command: ["sleep", "3600"]
YAML
cleanup() {
    docker compose -p "$COMPOSE_PROJECT_NAME" -f "$COMPOSE_FILE" down -v --remove-orphans || true
    rm -rf "$dir"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
docker compose -p "$COMPOSE_PROJECT_NAME" -f "$COMPOSE_FILE" up -d --wait
export STATBUS_LIVE_DB_TEST=1
# Explicit names, rather than running all cmd/upgrade tests with the guard
# relaxed. -v provides CI evidence that each probe actually ran.
go test -C "$workspace/cli" -count=1 -v ./cmd ./internal/upgrade \
    -run '^(TestExtractSeedFromImage|TestSourceServingExpectedImageReferencesRendersActualRepoComposeModel|TestComposePsListsExistingProfiledContainersWithoutProfileSelection)$'
