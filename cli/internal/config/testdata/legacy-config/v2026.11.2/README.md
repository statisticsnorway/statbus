# v2026.11.2 legacy config fixture

- Tag: `v2026.11.2`
- Commit: `929fe787c2ab323d3a8c6d013bb9864fbec7bd67`
- Capture command: `cli/internal/config/testdata/legacy-config/capture.sh v2026.11.2`

Captured by building this tag's own Go CLI with the release ldflags, seeding only
`CADDY_DEPLOYMENT_MODE=development` and `SITE_DOMAIN=local.statbus.org`, and
running `sb config generate` in that tag's detached worktree. Secret values are
replaced with deterministic `fixture-*` placeholders. Keys and file placement
are unchanged.
