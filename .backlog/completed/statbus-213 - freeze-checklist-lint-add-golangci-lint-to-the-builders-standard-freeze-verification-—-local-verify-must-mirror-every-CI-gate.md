---
id: STATBUS-213
title: >-
  freeze-checklist-lint: add golangci-lint to the builders' standard freeze
  verification — local verify must mirror every CI gate
status: Done
assignee:
  - foreman
created_date: '2026-08-17 03:57'
updated_date: '2026-08-27 13:50'
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
- [x] #1 The freeze-verification checklist (wherever it canonically lives after this ticket) names golangci-lint with the CI-pinned version for Go-touching units
- [x] #2 A builder's freeze report on the next Go unit shows the lint oracle run locally
- [ ] #3 No CI go-lint red on a commit whose freeze reported the full chain green
<!-- AC:END -->

## Comments

<!-- COMMENTS:BEGIN -->
author: foreman
created: 2026-08-18 09:49
---
AC#1 closed: the checklist's canonical home is the builder role docs — .claude/team/engineer.md and .claude/team/mechanic.md both now name golangci-lint at the CI-pinned v2.12.2 (byte-matching go-test.yaml's lint job via cli/.golangci.yml) as mandatory freeze verification for Go-touching units, with the pinned-tag install command from go-test.yaml:108 recorded in engineer.md. AC#2 closed by observation — already satisfied twice today before codification: the engineer's 216/217 freeze reports both ran golangci-lint 2.12.2 locally and named the result (his reports confirmed the version against CI's pin). AC#3 stays open as the standing observation: it closes when the next several Go-carrying commits show no CI go-lint red against full-chain-green freezes — checked at stable promotion, then the ticket goes Done.
---
<!-- COMMENTS:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Freeze-checklist lint (documented in role docs, 2026-08-18): golangci-lint added to builder freeze verification for Go-touching units, pinned to v2.12.2. AC#1–#2 code-side; AC#3: standing observation for no CI go-lint red on commits with full-chain-green freezes (monitored at promotion).
<!-- SECTION:FINAL_SUMMARY:END -->
