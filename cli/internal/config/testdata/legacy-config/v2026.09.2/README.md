# v2026.09.2 legacy config fixture

- Tag: `v2026.09.2`
- Commit: `fe4a769a743dbf23990d1288a87742d93520391a`
- Capture command: `cli/internal/config/testdata/legacy-config/capture.sh v2026.09.2`

Captured by building this tag's own Go CLI with the release ldflags, seeding only
`CADDY_DEPLOYMENT_MODE=development` and `SITE_DOMAIN=local.statbus.org`, and
running `sb config generate` in that tag's detached worktree. Secret values are
replaced with deterministic `fixture-*` placeholders. Keys and file placement
are unchanged.
