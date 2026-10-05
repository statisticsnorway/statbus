# v2026.09.3 legacy config fixture

- Tag: `v2026.09.3`
- Commit: `ebe058afca76f915d03b3567a25386f8f3025e8f`
- Capture command: `cli/internal/config/testdata/legacy-config/capture.sh v2026.09.3`

Captured by building this tag's own Go CLI with the release ldflags, seeding only
`CADDY_DEPLOYMENT_MODE=development` and `SITE_DOMAIN=local.statbus.org`, and
running `sb config generate` in that tag's detached worktree. Secret values are
replaced with deterministic `fixture-*` placeholders. Keys and file placement
are unchanged.
