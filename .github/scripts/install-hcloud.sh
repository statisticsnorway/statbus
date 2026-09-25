#!/usr/bin/env bash
# Shared pinned CLI install for all Hetzner fleet jobs.
set -euo pipefail
version="${HCLOUD_CLI_VERSION:-1.64.1}"
url="https://github.com/hetznercloud/cli/releases/download/v${version}/hcloud-linux-amd64.tar.gz"
archive="$(mktemp)"
trap 'rm -f "$archive"' EXIT
for attempt in 1 2 3 4 5; do
  if curl -fsSL "$url" -o "$archive" && sudo tar -C /usr/local/bin -xzf "$archive" hcloud && hcloud version; then
    exit 0
  fi
  if [ "$attempt" -lt 5 ]; then
    echo "hcloud CLI install attempt ${attempt}/5 failed; retrying in $((attempt * 10))s" >&2
    sleep $((attempt * 10))
  fi
done
echo "::error title=hcloud CLI install failed::5 attempts; GitHub release download or installation unavailable, not a scenario finding" >&2
exit 1
