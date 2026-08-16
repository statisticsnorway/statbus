---
id: STATBUS-209
title: >-
  restore-readonly-completion: after rollback DB restore, the next install pass
  completes but its completion INSERT hits a read-only database
status: In Progress
assignee:
  - engineer
created_date: '2026-08-16 22:29'
updated_date: '2026-08-16 22:34'
labels:
  - upgrade-recovery
  - release
dependencies: []
references:
  - cli/internal/install/install.go
  - cli/internal/upgrade/service.go
  - test/install-recovery/arcs/rollback-pair-terminal-arc.sh
  - test/install-recovery/arcs/restore-broke-reattempt-arc.sh
priority: high
ordinal: 209000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
> NORTH STAR: an install pass that prints "Installation complete!" has durably recorded its completion; a database restored by rollback is fully writable for the next attempt.
> FOUND: overnight arc triage 2026-08-17, v2026.08.0-rc.01 arc run 31970534502 — TWO arcs, SAME signature, both genuine product failures (ran post-stampede, 12-17 min real execution): rollback-pair-terminal (job 95222617643→95222618643) and restore-broke-reattempt (95222618662).

SIGNATURE (identical in both): the 4th dispatch's `./sb install` runs the FULL ladder — "[16/16] Upgrade service DONE ... Installation complete!" — and then: `INVARIANT POST_COMPLETION_UPGRADE_ROW_INSERT_SUCCEEDS violated: could not record completed upgrade row for sha=5d141d3ca...: ERROR: cannot execute INSERT in a read-only transaction (SQLSTATE 25006) (install.go:2450)`. The arc expected exit 0 on a clean pass; got 1. Both arcs had earlier driven ROLLBACK_FAILED_DB_RESTORE ("two consecutive crash-deaths during rollback") and the reattempt/restore machinery — the failing pass runs against a database the rollback path RESTORED.

HYPOTHESIS (unverified — needs the architect's read of the restore path): the restore leaves the database in a read-only state (default_transaction_read_only or equivalent protective setting) that the subsequent install pass never clears; the pass makes no earlier writes (idempotent refresh path — "All migrations are up to date"), so the completion INSERT is the FIRST write and the first to reveal it. Candidate mechanisms to check: (a) restore protection set during restore and not lifted on some path; (b) the protective setting CAPTURED INTO the backup itself (taken while protection was active) and faithfully restored — a persistence loop; (c) "Running post-restore fixups..." not running or not covering this setting on this path. The invariant did its job — this was previously a silent completion-recording failure class.

Note: the read-only state would poison EVERY later write on the box, not just the completion row — app writes included. Severity is data-plane, not bookkeeping.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Mechanism established from the restore path code (not hypothesis): where the read-only state comes from and why the next pass keeps it
- [ ] #2 Fix architect-ruled and landed: a rollback-restored database is fully writable for the next attempt, with the write-path proven by the arcs
- [ ] #3 rollback-pair-terminal and restore-broke-reattempt green at an RC tag
<!-- AC:END -->

## Comments

<!-- COMMENTS:BEGIN -->
author: architect
created: 2026-08-16 22:33
---
RULING (architect, overnight). The hypothesis lanes collapse into one invariant once the capture mechanism is seen: the read-only window engages BEFORE the snapshot (executeUpgrade: window → stop → backup — deliberate, it makes the snapshot the data-safe restore point), and the ALTER DATABASE persists in the catalog, INSIDE the data files. Therefore EVERY snapshot this pipeline takes carries an ENGAGED window by construction — lane (b) is not a bug, it is the design — and every restore resurrects it. The defect is lane (a) narrowed: A RESTORE THAT DOES NOT LIFT. The ratified contract already says writes are blocked 'until completion or rollback' — a restored box staying read-only violates it, so this fix is doctrine-compliance, not doctrine change.

THE FIX — THE RESTORE OWNS THE LIFT (chokepoint-owns-invariant, the 200/204 shape): wherever a snapshot restore completes and the restored DB reaches health, the window lifts before any non-exempt work can run. One helper owning restore→db-health→windowOff; the builder WALKS ALL restoreDatabase callers and routes them through it — the daemon rollback tail (which may already lift — verify, don't assume; the failing arcs are the STATBUS-111 replay ladder and the pair-terminal path, where the lift is evidently absent), the 111 replay, every recovery restore, and 200's restoreSourceServices (already lifts post-health — confirm it conforms to the helper rather than duplicating).

REJECTED: lane (c), a blanket lift in post_restore.sql — post_restore runs on EVERY migrate up including inside an ACTIVE upgrade window; a blanket lift there would tear down the very protection mid-upgrade. The lift belongs solely to restore-completion.

SEVERITY CONFIRMED as filed: this is data-plane (a restored box silently refusing all writes), and the fact it surfaced as a LOUD insert failure instead of silence is the 197-era invariant working. ORACLES: RED-first unit on the replay path (restore → health → window state read must be OFF); both arcs green at rc.02; the exemption discipline untouched (pipeline sessions still self-exempt — no widening).
---
<!-- COMMENTS:END -->
