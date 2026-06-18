---
id: STATBUS-097
title: >-
  migration-atomicity: scope making apply+record atomic to close the
  commit-vs-record window
status: To Do
assignee: []
created_date: '2026-06-18 21:36'
labels:
  - upgrade
  - migration
  - design-scoping
dependencies: []
priority: low
ordinal: 97000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
From the King's no-residual rule (2026-06-18), applied to the one residue the fingerprint/kill reshape leaves behind.

THE WINDOW: when a migration commits, there is a ~millisecond gap before the system records that it ran (the db.migration INSERT, done in Go after psql returns). If the process dies in that gap, the migration is applied-but-unrecorded — a torn state. It is too small to hit by external timing, so it is the one crash point the NOTIFY-handshake / external-kill approach cannot reproduce.

THE CLEAN FIX (the King's rule): make "apply" and "record" ONE atomic step — fold the db.migration INSERT into the migration's own transaction — so the torn state CANNOT exist. Then there is nothing to test and no hook needed.

THE WRINKLE: some migrations legitimately cannot run in a single transaction (CREATE INDEX CONCURRENTLY, some ALTER TYPE, VACUUM). For those the window is intrinsic.

SCOPE THIS (read-only first, no product change yet):
1. Count how many real migrations in migrations/ cannot run in one transaction (concurrent index builds, etc.) — with the list.
2. Recommend: make apply+record atomic for the transactional majority (removes the window for them); for the non-transactional exceptions, either keep ONE minimal inject hook for that window or accept it untested. Present the count so the King decides the policy.

Source: King, 2026-06-18 — asked whether to open this as its own entry; opened. Not blocking the immediate arc work.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 A count + list of migrations in migrations/ that cannot run in a single transaction
- [ ] #2 A written recommendation: atomic apply+record for the transactional majority, and a proposed policy for the non-transactional exceptions (minimal hook vs accept-untested)
- [ ] #3 The King's policy decision recorded BEFORE any product change is made
<!-- AC:END -->
