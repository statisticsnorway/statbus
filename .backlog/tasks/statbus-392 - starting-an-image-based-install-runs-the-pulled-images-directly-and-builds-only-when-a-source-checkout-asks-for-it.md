---
id: STATBUS-392
title: >-
  Starting an image-based install runs the pulled images directly, and builds
  only when a source checkout asks for it
status: To Do
assignee: []
created_date: '2026-09-24 16:42'
updated_date: '2026-09-24 14:53'
labels:
  - install
dependencies: []
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

## Goal

`./sb start` on an image-based install starts the pulled images directly. It
builds only when the operator asks (`./sb build`) or a source development
checkout needs it.

## Done when

- In development mode on an image-based install, `./sb start all` starts
  within seconds using pulled images.
- In a source checkout, the development build still happens.
