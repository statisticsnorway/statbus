---
id: STATBUS-385
title: >-
  Before starting anything, the installer names the program using a port StatBus
  needs and how to free it
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

Apache occupied port 80 on the Ubuntu 26.04 host. The install reached Docker
startup and surfaced only a generic container failure instead of identifying the
conflicting process. The triage finds no port preflight in
`cli/cmd/install.go:945-954`; standalone also needs 443 and 5431 (the triage
calls out the configured database port, with 5432 for the TLS listener).

## Goal

Before starting any container, the installer checks each address and port the
chosen mode binds (80, 443 and the database ports for standalone) and, for any
port in use, tells the operator which program holds it and how to free it or
pick a mode that avoids it.

## Done when

- With Apache on port 80, the operator sees "port 80 is used by apache2"
  (or the actual owner) plus the stop command and the alternative mode, before
  any container starts.
- With all ports free, the preflight passes silently and install continues.
