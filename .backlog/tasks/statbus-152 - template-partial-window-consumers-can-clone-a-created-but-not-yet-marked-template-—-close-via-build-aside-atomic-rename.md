---
id: STATBUS-152
title: >-
  template-partial-window: consumers can clone a created-but-not-yet-marked
  template — close via build-aside + atomic rename
status: In Progress
assignee:
  - mechanic
created_date: '2026-07-09 00:08'
updated_date: '2026-07-12 03:32'
labels:
  - testing
  - tooling
dependencies:
  - STATBUS-141
references:
  - dev.sh
  - STATBUS-141
priority: low
ordinal: 153000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
> NORTH STAR: a template consumer can never observe a partially-initialized test template — neither a missing one (closed by STATBUS-141) nor a created-but-not-yet-marked one (this ticket).
> STAGE: Testing foundation. FOUND: the mechanic's honest scope note during the 141 build (2026-07-09); ruled a separate ticket by the architect in the 141 ship verdict.
> COMPLEXITY: mechanic-simple; the fix direction is PRE-RULED (below) — buildable when its turn comes.
> DEPENDS ON: STATBUS-141 (shipped).

THE WINDOW: 141's advisory lock (59328) covers create-test-template's drop + CREATE DATABASE — the observed mid-clone race. It cannot extend across the JWT-secret insert and the final IS_TEMPLATE=true/ALLOW_CONNECTIONS=false remark that follow, because those connect to the template database itself and pg_advisory_lock is session-scoped to the -d postgres session (a \\c reconnect drops the lock — mechanic-traced). In that sub-second window a consumer holding 59328 could clone a template that exists but lacks the JWT secret / template marking. Pre-existing behavior, unchanged by 141, now named.

PRE-RULED FIX (architect, 141 ship verdict, 2026-07-09): build-aside-rename-atomically. Create the clone as ${TEMPLATE_NAME}_building (no lock needed — nobody clones that name); do the JWT insert + IS_TEMPLATE/ALLOW_CONNECTIONS remark against the _building DB at leisure; then take advisory lock 59328 for milliseconds: terminate + DROP old + ALTER DATABASE ... RENAME into place + unlock. Closes BOTH races (mid-clone and half-initialized) and shrinks the locked section to a rename — strictly better than extending lock coverage, which session-scoping forbids.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 create-test-template builds the clone aside as ${TEMPLATE_NAME}_building, fully initializes it (JWT secret, IS_TEMPLATE, ALLOW_CONNECTIONS), then swaps it into place under advisory lock 59328 via terminate + drop-old + RENAME
- [ ] #2 A consumer clone concurrent with a rebuild observes either the old complete template or the new complete template — never a partial or missing one
<!-- AC:END -->
