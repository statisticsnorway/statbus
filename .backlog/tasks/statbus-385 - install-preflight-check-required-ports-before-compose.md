---
id: STATBUS-385
title: >-
  Install preflight must detect occupied HTTP HTTPS and standalone database ports
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

Apache occupied port 80 on the Ubuntu 26.04 host. The install reached Docker
startup and surfaced only a generic container failure instead of identifying the
conflicting process. The triage finds no port preflight in
`cli/cmd/install.go:945-954`; standalone also needs 443 and 5431 (the triage
calls out the configured database port, with 5432 for the TLS listener).

## Done when

Before compose startup, install checks every bind address/port required by the
selected mode, names the owning process, and gives a mode/stop remedy.
