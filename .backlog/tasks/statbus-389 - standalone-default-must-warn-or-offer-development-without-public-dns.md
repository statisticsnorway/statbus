---
id: STATBUS-389
title: >-
  Install must not silently choose standalone when the configured domain has no public DNS
status: To Do
assignee: []
created_date: '2026-09-24 16:42'
updated_date: '2026-09-24 16:42'
labels:
  - install
priority: high
type: bug
ordinal: 1
---

## Finland v2026.09.2 evidence (2026-09-24)

The Finland operator selected standalone with `statbus.statfin.eu`, but the
triage records `dig +short` as empty. Standalone binds 80/443, requests ACME,
and exposes TLS PostgreSQL, which does not fit this laptop. The default is in
`installinput/config.go:30-31`; ACME behavior is in
`caddy/templates/standalone.caddyfile.tmpl:151-154`.

## Done when

Configuration resolves the domain and warns or refuses when it cannot resolve
to the host, offering development mode or requiring explicit certificates
before selecting public standalone behavior.
