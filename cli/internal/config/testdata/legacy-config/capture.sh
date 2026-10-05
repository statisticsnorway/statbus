#!/usr/bin/env bash
set -euo pipefail

repo_root=$(git rev-parse --show-toplevel)
out_root="$repo_root/cli/internal/config/testdata/legacy-config"
if (( $# > 0 )); then
  tags=("$@")
else
  tags=(v2026.08.0 v2026.09.0 v2026.09.2 v2026.09.3)
fi

normalize() {
  awk -F= '
    BEGIN { OFS="=" }
    /^[[:space:]]*#/ || !index($0, "=") { print; next }
    {
      key=$1
      if (key == "GITHUB_TOKEN" || key == "SLACK_TOKEN" || key == "SEQ_API_KEY" ||
          key == "JWT_SECRET" || key == "POSTGRES_ADMIN_PASSWORD" ||
          key == "POSTGRES_APP_PASSWORD" || key == "POSTGRES_AUTHENTICATOR_PASSWORD" ||
          key == "POSTGRES_NOTIFY_PASSWORD" || key == "DASHBOARD_PASSWORD" ||
          key == "SERVICE_ROLE_KEY") {
        print key, "fixture-" tolower(key)
        next
      }
      print
    }
  ' "$1"
}

for tag in "${tags[@]}"; do
  commit=$(git rev-list -n 1 "$tag")
  worktree=$(mktemp -d "${TMPDIR:-/tmp}/statbus-445-${tag}.XXXXXX")
  binary="$worktree/sb-release"
  cleanup() {
    git -C "$repo_root" worktree remove --force "$worktree/source" >/dev/null 2>&1 || true
    rm -rf "$worktree"
  }
  trap cleanup EXIT

  git -C "$repo_root" worktree add --detach "$worktree/source" "$tag"
  (
    cd "$worktree/source/cli"
    go build -trimpath \
      -ldflags "-X 'github.com/statisticsnorway/statbus/cli/cmd.version=$tag' -X 'github.com/statisticsnorway/statbus/cli/cmd.commit=$commit'" \
      -o "$binary" .
  )

  # Development is an explicit operator choice and avoids inventing a public
  # domain. Every other key and value placement comes from this tag's generator.
  printf 'CADDY_DEPLOYMENT_MODE=development\nSITE_DOMAIN=local.statbus.org\n' > "$worktree/source/.env.config"
  (cd "$worktree/source" && "$binary" config generate)

  destination="$out_root/$tag"
  mkdir -p "$destination"
  normalize "$worktree/source/.env.config" > "$destination/.env.config"
  if test -f "$worktree/source/.env.credentials"; then
    normalize "$worktree/source/.env.credentials" > "$destination/.env.credentials"
  else
    rm -f "$destination/.env.credentials"
  fi
  cat > "$destination/README.md" <<EOF
# $tag legacy config fixture

- Tag: \`$tag\`
- Commit: \`$commit\`
- Capture command: \`cli/internal/config/testdata/legacy-config/capture.sh $tag\`

Captured by building this tag's own Go CLI with the release ldflags, seeding only
\`CADDY_DEPLOYMENT_MODE=development\` and \`SITE_DOMAIN=local.statbus.org\`, and
running \`sb config generate\` in that tag's detached worktree. Secret values are
replaced with deterministic \`fixture-*\` placeholders. Keys and file placement
are unchanged.
EOF

  cleanup
  trap - EXIT
done
