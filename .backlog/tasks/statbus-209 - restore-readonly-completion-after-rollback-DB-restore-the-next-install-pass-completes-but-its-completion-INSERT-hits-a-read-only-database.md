---
id: STATBUS-209
title: >-
  restore-readonly-completion: after rollback DB restore, the next install pass
  completes but its completion INSERT hits a read-only database
status: In Progress
assignee:
  - engineer
created_date: '2026-08-16 22:29'
updated_date: '2026-08-16 22:42'
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

author: engineer
created: 2026-08-16 22:42
---
BUILD-TIME FINDINGS (engineer byte-walk on current HEAD, 2026-08-17) — the ruled mechanism ("route all restoreDatabase callers through one restore→health→windowOff helper") appears LARGELY ALREADY SATISFIED, so before building I need the architect to confirm the true gap. Details:

1. restoreDatabase (Service method) has exactly TWO non-test callers: service.go:7904 (inside restoreAndFinalize) and service.go:8335 (the rollback git-restore ABORT branch, which DELIBERATELY holds read-only ON — degraded box). restoreAndFinalize is the SHARED restore tail for BOTH d.rollback (call @8453) AND ReattemptRestore / the STATBUS-111 replay (call @8184).

2. restoreAndFinalize ALREADY LIFTS at service.go:7981 — `d.terminalExec(windowOffSQL)` with the ROLLBACK_READ_ONLY_WINDOW_LIFTED escalation — UNCONDITIONALLY, right after waitForDBHealth(7953)+reconnect(7958)+setMaintenance(7963), and BEFORE the degraded/failed branch (8008). So both callers already route through a lift. This contradicts “the lift is evidently absent.”

3. WHY THE ARCS STILL FAIL (two different mechanisms, same 25006 signature):
   • rollback-pair-terminal: the C9 kill site (killed-by-system-during-builtin-rollback, service.go:7934) sits BETWEEN restoreDatabase(7904) and the lift(7981). Dispatches 2+3 die there → the DB is restored (read-only ALTER captured in the snapshot) but the lift NEVER executes. The 4th (clean) dispatch fires rollbackResumeIsTerminal (restore-broke terminal) with NO third restore — so it never reaches restoreDatabase/7981 — brings the DB up via EnsureDBUp(service.go:1943), and the install completes → the completion INSERT (cli/cmd/install.go:2450) is the FIRST write → 25006.
   • restore-broke-reattempt phase(i): the 4th dispatch fires rollbackResumeIsTerminal THEN re-detects StateRestoreReattemptable and replays via ReattemptRestore → restoreAndFinalize → the 7981 lift SHOULD run — yet the install still hits 25006 at completion. So on that path the 7981 lift is either not running or does not stick to the later install-completion session.

OPEN QUESTIONS (build shape depends on these):
Q1. The real gap is NOT “a restoreDatabase caller missing a lift.” It is (a) the restore-broke-TERMINAL path (rollbackResumeIsTerminal, 4th dispatch) — no restoreDatabase call, so OUTSIDE “walk all restoreDatabase callers” — which brings a previously-restored (read-only) DB to health but never lifts; and (b) the reattempt’s lift not reaching the install completion. Should the helper key on “wherever a restored DB reaches health” (covering the terminal path + the install-completion boundary), rather than “at each restoreDatabase call”?
Q2. The failing write is cli/cmd/install.go:2450 (the fresh-install/completion INSERT), and EnsureDBUp/the terminal path also live partly in cli/cmd — OUTSIDE my scoped cli/internal/upgrade/*. Does this fix reach into cli/cmd/install.go (e.g. lift-on-completion, or run the boot backstop clearStaleReadOnlyWindow@service.go:3701 which `./sb install` may not currently invoke)? If so, is that in my lane for 209 or a coordination point?

HOLDING the build until the architect confirms the gap + scope. AC#1 (mechanism from code) is effectively answered above; AC#2’s fix shape hinges on Q1/Q2.
---
<!-- COMMENTS:END -->
