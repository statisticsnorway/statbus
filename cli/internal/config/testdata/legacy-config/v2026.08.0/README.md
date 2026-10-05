# v2026.08.0 legacy config fixture

- Tag: `v2026.08.0`
- Commit: `2b4b4ef6cdc36582744da2c290126d431ea09fbc`
- Capture command: `cli/internal/config/testdata/legacy-config/capture.sh v2026.08.0`

Captured by building this tag's own Go CLI with the release ldflags, seeding only
`CADDY_DEPLOYMENT_MODE=development` and `SITE_DOMAIN=local.statbus.org`, and
running `sb config generate` in that tag's detached worktree. Secret values are
replaced with deterministic `fixture-*` placeholders. Keys and file placement
are unchanged.
