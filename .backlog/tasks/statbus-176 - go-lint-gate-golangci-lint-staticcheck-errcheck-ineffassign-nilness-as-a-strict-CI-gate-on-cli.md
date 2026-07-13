---
id: STATBUS-176
title: >-
  go-lint-gate: golangci-lint (staticcheck, errcheck, ineffassign, nilness) as a
  strict CI gate on cli/
status: To Do
assignee: []
created_date: '2026-07-13 14:42'
labels:
  - ci
  - quality-gate
  - go
dependencies: []
priority: medium
ordinal: 177000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
King-approved quality gate. Add golangci-lint to CI covering the Go CLI (cli/), with exactly these analyzers enabled: staticcheck, errcheck, ineffassign, nilness.

Shape (per the ratified strict-gating doctrine): a strict job that FAILS the workflow on any finding — no continue-on-error hedges. If a bypass is ever needed it must be loud and explicit (SKIP_GO_LINT=1 style), never a silently-tolerated red job.

Rollout: first run will surface a backlog of existing findings. Burn them down in the same unit or in an immediately-following series of small commits — do not land the gate in a permanently-red or bypassed state.

Config lives in cli/.golangci.yml so local `golangci-lint run` matches CI exactly.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 CI job runs golangci-lint on cli/ with staticcheck, errcheck, ineffassign, nilness enabled and fails the workflow on any finding
- [ ] #2 No continue-on-error on the lint job; any bypass is an explicit loud env toggle
- [ ] #3 Existing findings burned down so the gate lands green on master
- [ ] #4 cli/.golangci.yml checked in so local runs match CI
<!-- AC:END -->
