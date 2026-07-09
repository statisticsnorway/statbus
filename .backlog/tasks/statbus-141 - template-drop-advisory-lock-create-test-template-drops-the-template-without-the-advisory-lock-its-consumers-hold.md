---
id: STATBUS-141
title: >-
  template-drop-advisory-lock: create-test-template drops the template without
  the advisory lock its consumers hold
status: Done
assignee:
  - mechanic
created_date: '2026-07-06 15:13'
updated_date: '2026-07-09 00:12'
labels:
  - testing
  - tooling
dependencies:
  - STATBUS-133
references:
  - dev.sh
  - STATBUS-133
ordinal: 142000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
> NORTH STAR: (as filed) a template consumer must never have the test template dropped out from under it mid-clone.
> BENEFIT: closes the last manufactured-flaky source in the template family — a type/doc generation cloning the template can no longer lose it to a concurrent rebuild, so a "template not found / clone failed" mid-generation red can never again masquerade as a real failure. Completes the guard 133 deliberately left to the finer-grained DB lock.
> STAGE: Testing foundation (Stage 1 support).
> COMPLEXITY: mechanic-simple — take advisory lock 59328 around the drop/recreate in create-test-template (dev.sh:1375-1399), matching the consumers' existing locking; single site.
> DEPENDS ON: STATBUS-133 (same dev.sh region; land after its commit to avoid conflicting edits).
> Note: filed this morning with priority "low" — the exact pattern this revision kills; the field clears with the rest in the apply pass.

---

NORTH STAR: test results must be trustworthy — a test-template consumer (type/doc generation cloning the template under DB advisory lock 59328) must never have the template dropped out from under it mid-clone. STAGE: Testing foundation (supports Stage 1 of the STATBUS-036 roadmap).

FOUND during the STATBUS-133 review (architect, 2026-07-06): template CONSUMERS (generate-types, generate-doc-db) clone under DB advisory lock 59328 — the right finer-grained guard — but create-test-template's template DROP (dev.sh:1375-1399) does NOT take 59328. Consumer-vs-rebuild therefore has a one-sided race: a rebuild can drop the template while a consumer is mid-clone. STATBUS-133's serialization lock narrows the window (rebuilds now serialize against each other and against suite runs) but does not close consumer-vs-rebuild, because consumers are deliberately not gated by the coarse lock.

FIX: take advisory lock 59328 around the template drop/recreate in create-test-template, matching the consumers' existing locking. Small, single-site.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 The template drop/recreate path holds advisory lock 59328 for the duration, same as the consumers
- [x] #2 A consumer clone concurrent with a rebuild either completes or waits — never loses the template mid-clone
<!-- AC:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
SHIPPED ad080611b (dual-reviewed: architect ship with the keep-in-sync comment pair ordered; foreman first-hand). create-test-template's drop + recreate now run as ONE held psql session under DB advisory lock 59328 — lock first statement, unlock last — matching the consumers' exact pattern (generate-types dev.sh:1883-1889, generate-doc-db :1945-1951, shared-tests :892-897). The session-scoped lock forced inlining seed-clone's CREATE DATABASE statement (subprocess = separate connection = lost lock; both middle roads verified failing: subcommand-takes-lock deadlocks under the holding parent, release-then-reacquire reopens the drop→create gap); both sites carry mutual keep-in-sync comments as the anti-drift device. AC#2 holds structurally: a consumer holding 59328 either sees the old template or waits through the entire drop+create. The residual post-unlock window (created-but-not-yet-marked template) was honestly flagged by the mechanic, ruled out of scope, and ticketed as STATBUS-152 with a pre-ruled build-aside + atomic-rename design.
<!-- SECTION:FINAL_SUMMARY:END -->
