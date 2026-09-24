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

The image-build behavior was noted in triage, but its original code citation does not exist at master `7a9cf707e`; the exact implementation location and observation source are not determined. Verify whether development mode adds `--build` on image-based installs before implementing the proposed change. This can turn a mode change or recovery into an unexpected local
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
