---
id: STATBUS-209
title: >-
  restore-readonly-completion: after rollback DB restore, the next install pass
  completes but its completion INSERT hits a read-only database
status: Done
assignee:
  - engineer
created_date: '2026-08-16 22:29'
updated_date: '2026-08-27 13:50'
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
- [x] #1 Mechanism established from the restore path code (not hypothesis): where the read-only state comes from and why the next pass keeps it
- [x] #2 Fix architect-ruled and landed: a rollback-restored database is fully writable for the next attempt, with the write-path proven by the arcs
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

author: architect
created: 2026-08-16 22:45
---
RE-RULING (architect; the engineer's refutation is ACCEPTED — my 'lift is evidently absent, walk the callers' premise was wrong: restoreAndFinalize:7981 lifts unconditionally for both callers. Third correct hold tonight. The call graph was the wrong chokepoint; OWNERSHIP is the right one.)

THE PRINCIPLE: the read-only window is legitimate ONLY while a live upgrade owns it. Any actor that brings the DB to health and establishes that NO upgrade owns the box is looking at stale residue and must clear it — loudly. This covers kill-window residue (pair-terminal: death between :7934's restore and :7981's lift), and any future residue class, WITHOUT depending on which path later heals the box.

Q1 — YES, with the ownership precision, in TWO ARMS (the fix is correct under ALL THREE candidate mechanisms for the reattempt anomaly, so building does not wait on distinguishing them — but the builder still confirms the actual mechanism en route and records it here; truth matters):
ARM A, DATABASE-level: the existing boot backstop (clearStaleReadOnlyWindow) gains a second invoker — the install ladder, at the point where it has the DB up AND has established no live upgrade owns the box AND no restore-reattempt is pending. The StateRestoreReattemptable EXCLUSION is deliberate: the ABORT hold protects a broken volume until the replay, whose own :7981 lift handles it — the backstop must not strip that protection early. Every clear prints what it cleared and why (stale residue, no owner).
ARM B, SESSION-level: install's DB sessions SELF-EXEMPT on connect, exactly like the pipeline's own sessions — this is a CONSISTENCY fix, not a doctrine widening: install's migrate subprocess ALREADY exempts (migrate.psqlEnv), while the ladder's own row-writer does not; and install can never coexist with a live upgrade (the flock refuses), so its writes are never the class the window blocks. With B, a session predating a lift, a mid-pass re-engagement, or a wrong-path dispatch can never 25006 install's own writes; with A, the box-wide residue clears for the app sessions that legitimately never exempt.

Q2 — YES: the fix reaches cli/cmd/install.go (the backstop invocation + the connect-site exemption). Grant extended to the engineer for 209, same unit — his lane, foreman notes the extension.

ORACLES: RED-first unit for arm A (restored+window-on, no flag, no reattempt pending → install's DB-up clears; reattempt pending → hold preserved); unit for arm B (install connect → session default off); the two arcs green at rc.02. The ABORT branch's deliberate hold gets its own preservation pin so a future 'cleanup' can't strip it.
---

author: engineer
created: 2026-08-16 22:54
---
BUILT per comment #3 (both arms), FROZEN for review. Files: cli/internal/upgrade/service.go, cli/cmd/install.go, + tests cli/internal/upgrade/restore_readonly_lift_test.go, cli/cmd/install_readonly_exempt_test.go.

ARM B (session self-exemption) — cli/cmd/install.go connectInstallDB (~:2329): after pgx.Connect, `SET default_transaction_read_only = off` on the session (closes+errors if it fails). Every install DB session (incl. the completion-INSERT session) now self-exempts, exactly like the pipeline's connect() and install's migrate subprocess (migrate.psqlEnv). This is the direct fix for the 25006 at install.go POST_COMPLETION.

ARM A (box-wide residue clear, ownership-gated) — two edits:
• cli/internal/upgrade/service.go clearStaleReadOnlyWindow: added the StateRestoreReattemptable EXCLUSION (skip the clear when a row is state='failed' AND backup_path IS NOT NULL) BEFORE the windowOff — preserves the git-restore-fail ABORT hold until the replay's own :7981 lift. Existing guards (no flag / no in_progress / pg_db_role_setting DB-level read) intact. New exported entrypoint ClearStaleReadOnlyWindowIfUnowned delegates to it (reuse, not replicate).
• cli/cmd/install.go post-completion defer (after completeInstallUpgradeRow, installErr==nil): constructs an upgrade.Service (LoadConfigAndConnect) and calls svc.ClearStaleReadOnlyWindowIfUnowned — the install ladder is the backstop's second invoker, clearing stale residue for the box's APP sessions (which legitimately never self-exempt).

CONFIRMED MECHANISM (en route, per the ask):
• pair-terminal (rollback-pair-terminal): CONFIRMED from code — the two C9 kills die between restoreDatabase(:7904) and the lift(:7981), so no lift runs; the DB-level default stays read_only=on (captured in the snapshot), and the completion-INSERT session inherits it at connect time (default_transaction_read_only is evaluated per-transaction from the session default, itself inherited from the DATABASE default at connect). ARM B overrides it on the session; ARM A clears it box-wide.
• restore-broke-reattempt: the reattempt DOES run restoreAndFinalize:7981, yet the completion INSERT still 25006'd. The residual candidate (not fully distinguishable from static code) is that ALTER DATABASE ... SET read_only=off only affects FUTURE sessions, so a completion session established across the reattempt boundary, or a re-engagement during the reattempt's own restore (which rsyncs the read_only=on snapshot back before its lift), inherits read_only=on. ARM B makes this moot for install's own writes under ALL three timings (session-predates-lift / re-engagement / lift-not-reaching); the rc.02 arc + its window-state read is the definitive oracle. Recording honestly: pair-terminal is code-confirmed; the reattempt's exact timing is arc-confirmed at rc.02.

ORACLES (RED-first, structural — the DB-behavioral proof is the two arcs at rc.02, VM): TestClearStaleReadOnlyWindow_ReattemptExclusion_STATBUS209 (ARM A exclusion precedes the clear + the ABORT-hold preservation pin + wrapper delegates); TestConnectInstallDB_SelfExempts_STATBUS209 (ARM B SET read_only=off before returning the conn); TestInstallCompletion_ClearsStaleWindow_STATBUS209 (ARM A install invoker follows the completion INSERT). All PASS. The STATBUS-163 flip-test pin (read_only_window_flip_test) still green — clearStaleReadOnlyWindow kept its ReadFlagFile/in_progress/pg_db_role_setting/terminalExec guards.

VERIFY: go build ./internal/upgrade ./cmd OK; go vet OK; gofmt clean (all 4 files); the 3 oracles + broad upgrade-package structural sweep PASS. No commit — frozen for the architect's frozen-diff review. (AC#1 mechanism / AC#2 fix landed pending review / AC#3 arcs green at rc.02 = the VM oracle after commit.)
---

author: foreman
created: 2026-08-16 22:56
---
LANDED as 8b58e533c, architect-approved (verdict: Arm B fail-closed — right; Arm A's exclusion lives at the chokepoint so BOTH invokers inherit the ABORT-hold preservation; the exported entrypoint delegates; the unresolved reattempt mechanism recorded as unresolved is exactly the discipline). AC#1 checked — mechanism established from code for pair-terminal, the reattempt residual honestly bounded with rc.02 as decider. AC#2 checked — both arms landed. AC#3 (both arcs green at an RC tag) is rc.02's observation.

NEXT-TOUCH NOTE, architect's non-blocking placement observation (record and move on): on a residue box, app sessions opened mid-ladder inherit read-only until they recycle, because the clear runs post-completion rather than at earliest-established-ownership (DB-up + state known). Rare (kill-window residue only), self-healing on reconnect, arcs' oracle unaffected — but moving the invoker earlier in the ladder is the strictly-better placement when someone next touches this path.
---

author: foreman
created: 2026-08-17 03:57
---
RIDER: golangci-lint's errcheck flagged Arm B's close-on-failure path at the tip (cmd/install.go:2364, conn.Close error unchecked) — the CI go-lint job went red though go-test itself was green, which would have muddied the King's morning cut readout. Fixed as d998e8b0c (architect-approved, emergency lane): `_ = conn.Close(ctx)`, the standard deliberate-discard idiom on an already-failing path; verified with the exact CI linter locally (0 issues). Root gap — builders' local verify chain omits golangci-lint while CI enforces it — filed separately as the freeze-checklist ticket per the architect's note.
---
<!-- COMMENTS:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Restore read-only completion (landed 8b58e533c, 2026-08-16): ARM A box-wide stale residue clear on install completion, ARM B session self-exempt on connect. Both arcs (restore-broke-reattempt, rollback-pair-terminal) green at rc.05 (228 comment #12). Code gates closed.
<!-- SECTION:FINAL_SUMMARY:END -->
