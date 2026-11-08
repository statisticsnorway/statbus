# v2026.11.1 legacy config fixture

- Tag: `v2026.11.1`
- Commit: `3282c0af77050d6b8b0c55c2357ea472fce59d56`
- Capture command: `cli/internal/config/testdata/legacy-config/capture.sh v2026.11.1`

Captured by building this tag's own Go CLI with the release ldflags, seeding only
`CADDY_DEPLOYMENT_MODE=development` and `SITE_DOMAIN=local.statbus.org`, and
running `sb config generate` in that tag's detached worktree. Secret values are
replaced with deterministic `fixture-*` placeholders. Keys and file placement
are unchanged.
