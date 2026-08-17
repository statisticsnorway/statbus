---
id: STATBUS-213
title: >-
  freeze-checklist-lint: add golangci-lint to the builders' standard freeze
  verification — local verify must mirror every CI gate
status: To Do
assignee: []
created_date: '2026-08-17 03:57'
labels:
  - quality-gate
  - process
dependencies: []
references:
  - .github/workflows/go-test.yaml
  - cli/.golangci.yml
priority: low
ordinal: 213000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
> NORTH STAR: a check that only exists in one place surprises at the other (the 205 layering lesson, one level down) — every gate CI enforces on a commit must be runnable and run in the builder's freeze-time verify chain.
> FOUND: 2026-08-17 overnight, post-209: the CI go-lint job (golangci-lint: staticcheck, errcheck, ineffassign, nilness per cli/.golangci.yml) went red at the tip on an errcheck finding in 209's Arm B (cmd/install.go conn.Close unchecked), though the builder's verify chain — build, vet, gofmt, tests — was green. Fixed as d998e8b0c; the gap is the process, not the code.

THE FIX: add `golangci-lint run ./...` (in cli/, the pinned v2.12.2 matching go-test.yaml's lint job byte-for-byte via cli/.golangci.yml) to the standard freeze-verification checklist for any Go-touching unit. Where that checklist lives is part of the work: today it is convention carried in dispatch briefs — either (a) codify it in the team role docs / a pre-freeze script the builders invoke, or (b) at minimum add it to the foreman's standard dispatch-brief oracle template. Confirm golangci-lint v2.12.2 availability in builder environments (it ran locally tonight — verify the version matches the CI pin, and note the install command from go-test.yaml:108 in place).

Architect's framing on file: "a one-line addition of golangci-lint to the standard freeze-verification checklist (or the pre-freeze script if one exists) closes it; file it as a low ticket when the morning settles."
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 The freeze-verification checklist (wherever it canonically lives after this ticket) names golangci-lint with the CI-pinned version for Go-touching units
- [ ] #2 A builder's freeze report on the next Go unit shows the lint oracle run locally
- [ ] #3 No CI go-lint red on a commit whose freeze reported the full chain green
<!-- AC:END -->
