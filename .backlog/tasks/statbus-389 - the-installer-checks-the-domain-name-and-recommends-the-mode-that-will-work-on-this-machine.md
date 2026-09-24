---
id: STATBUS-389
title: >-
  The installer checks the domain name and recommends the mode that will work on
  this machine
status: To Do
assignee: []
created_date: '2026-09-24 16:42'
updated_date: '2026-09-24 14:53'
labels:
  - install
dependencies: []
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

## Goal

During configuration the installer resolves the chosen domain, tells the
operator what it found, and recommends the mode that will work on this machine:
standalone when the domain points here, development (or standalone with
provided certificates) when it does not.

## Done when

- With a domain that resolves to this host, standalone is recommended and
  install proceeds.
- With a domain that has no public DNS (the Finland case), the operator sees
  the lookup result and is offered development mode or the certificate option,
  and the chosen mode is recorded in `.env.config`.
