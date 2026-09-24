---
id: STATBUS-392
title: >-
  Development mode start must not force a local build when images are already pulled
status: To Do
assignee: []
created_date: '2026-09-24 16:42'
updated_date: '2026-09-24 16:42'
labels:
  - install
priority: medium
type: bug
ordinal: 1
---

## Finland v2026.09.2 evidence (2026-09-24)

The triage notes `cli/internal/service/service.go:55` adds `--build` in
development mode even for image-based installs, while compose files contain
build blocks. This can turn a mode change or recovery into an unexpected local
build; the install path currently avoids it only because its Services step uses
plain `up -d`.

## Done when

`./sb start` builds only when explicitly requested or when a development
checkout requires it, and image-based installs start pulled images directly.
