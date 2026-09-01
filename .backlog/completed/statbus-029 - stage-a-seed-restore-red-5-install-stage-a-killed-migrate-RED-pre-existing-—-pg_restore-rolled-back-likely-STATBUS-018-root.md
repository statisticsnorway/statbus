---
id: STATBUS-029
title: >-
  stage-a-seed-restore-red: 5-install-stage-a-killed-migrate RED (pre-existing)
  — pg_restore rolled back (likely STATBUS-018 root)
status: Done
assignee:
  - architect
created_date: '2026-06-11 07:48'
updated_date: '2026-06-18 08:20'
labels:
  - install-recovery
  - harness
dependencies: []
priority: medium
ordinal: 29000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Run 27306718138 @ cd2f5d51f: 5-install-stage-a-killed-migrate FAIL (pre-existing red, not attempted tonight). Log: "✗ psql zombie still present (count=1)" + "Seed restore failed — will run all migrations" + pg_restore reported transaction rolled back (exit status 1). The seed-restore failure likely shares the root with STATBUS-018 (pg_restore --clean fails on sql_saga updatable-view triggers when restoring onto a populated DB → falls back to full migrations). The zombie-still-present assertion is the over-strict-zombie-assertion the architect flagged (D bucket). HARNESS, 0 product. Cross-link STATBUS-018. Does NOT block the RC cut.
<!-- SECTION:DESCRIPTION:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
ESCALATED to architect (foreman, 2026-06-15) — mechanic's relax-to-diagnostic fix HELD uncommitted. The mechanic's mechanism is right (checkSessionsClean's 5-min gate, install.go:1211, means a FRESH psql INSERT-statistical zombie is never detected → cleanOrphanSessions never triggered → zombie survives). BUT foreman found a GATE/ACTION ASYMMETRY: cleanOrphanSessions Phase 1 (install.go:1345-1355) kills `query ILIKE '%statistical_history%'` UN-AGED — the action WOULD kill the fresh zombie, but the gate (5-min) never triggers it. So either (A) the gate is intentionally conservative (multi-context healthy-migrate protection) → the scenario tests an impossible-by-design case AND the relax-to-diagnostic guts its stated purpose ('Validates Phase 1 cleanup of psql migrate-zombies') → re-design to test a realistic orphan (aged >5min / advisory-lock holder via un-aged Phase 2 / statbus-migrate-sql app); or (B) a real recovery GAP — at install/recovery time there's no concurrent healthy migrate, so the gate should detect the obvious fresh migrate-zombie the action already kills (a lock-holding orphan survives recovery) → fix checkSessionsClean. Architect to adjudicate + propose the minimal correct fix. On the critical path for the comprehensive-green; get it right over fast.

== ARCHITECT ADJUDICATION (2026-06-15, King-routed via foreman) — design-only, no code ==

VERDICT: NEITHER the mechanic's 'relax-to-diagnostic' NOR a blind 'un-age the gate' is correct. Closest to the foreman's (A), with a verified caveat that vindicates part of (B). The 029 scenario is MIS-MODELED; re-design it. Do NOT change checkSessionsClean's aging for the RC.

EVIDENCE (verified file:line):
- acquireAdvisoryLock (cli/internal/migrate/migrate.go:~566) holds the migrate_up advisory lock on a pgx.Conn tagged `statbus-migrate-<pid>`; subprocess psqls are tagged `statbus-migrate-sql-<pid>` (SubprocessAppNamePrefix). So a REAL killed-migrate orphan = a (possibly-lingering, idle) `statbus-migrate-<deadpid>` advisory holder + `statbus-migrate-sql-<deadpid>` statistical_* subprocess(es).
- The GATE checkSessionsClean: `advisory_holders` counts ONLY empty-app holders (COALESCE(app,'')=''); `leaked` counts psql/migrate-sql running statistical_* aged >5min. The ACTION cleanOrphanSessions: Phase 1 kills psql/migrate-sql un-aged on statistical_history; Phase 2 PID-probes advisory holders. Phase 2 runs ONLY when the gate triggers.
- 5-install-stage-d-advisory-zombie already tests the EMPTY-app advisory holder (rune PID-9962, old binary) → Phase 2 un-aged.

WHY 029 IS MIS-MODELED: it synthesizes a bare `./sb psql -c "INSERT statistical_history ... pg_sleep(600)"` (app='psql', NO advisory lock), kills it. That shape is NOT a realistic killed-migrate orphan (a real one holds the migrate_up advisory lock + uses statbus-migrate-sql subprocesses). A bare-psql, no-advisory, fresh statistical_* backend is SQL-indistinguishable from a live manual/external client → the gate CORRECTLY declines to force-kill it fresh (un-aging would over-kill live clients = a regression). So 029's assertion tests over-aggressive cleanup the product intentionally avoids. The mechanic's relax-to-diagnostic merely turns that into a vacuous observation of a non-event.

MINIMAL CORRECT FIX (for 029): RE-DESIGN to the REALISTIC orphan — synthesize a killed-migrate that leaves a `statbus-migrate-<deadpid>` advisory holder (dead/non-existent PID) + a `statbus-migrate-sql-<deadpid>` statistical_* subprocess; assert recovery cleans BOTH. This replaces the mis-modeled test AND exercises the recovery path that matters (Phase 2 PID-probe + Phase 1 sweep). Complements stage-d (empty-app holder) by covering the TAGGED holder + its subprocess.

VERIFIED DEEPER FINDING (flag, do NOT blind-fix in the RC): for a CURRENT-binary killed migrate, the tagged `statbus-migrate-<deadpid>` advisory holder is counted by NEITHER gate subquery (advisory_holders is empty-app-only; the idle holder runs no statistical_* query so leaked misses it). It is only caught once its statistical_* SUBPROCESS ages past 5min (then leaked triggers → Phase 2 probes the holder). If the subprocess already exited, the holder is missed until TCP-keepalive/MigrateUpTimeout. → a fresh current killed-migrate orphan can DELAY recovery (bounded by min(keepalive, 30m migrate timeout)). The PRINCIPLED fix (if the re-designed 029 confirms it) is PID-liveness-aware gate detection (count tagged advisory holders to TRIGGER Phase 2's authoritative probe), NOT age-relaxation. Recommend a SEPARATE follow-up task with its own RED→GREEN; do not bundle a gate redesign into this RC.

DO: re-design 029 (realistic orphan). DO NOT: un-age the gate; relax 029 to diagnostic. The mechanic's held fix should be dropped in favor of the re-design.

ARCHITECT VERDICT (2026-06-15, foreman accepted + verified). The scenario is MIS-MODELED — it builds a bare `./sb psql -c INSERT statistical_history...pg_sleep` (app='psql', NO advisory lock), which is SQL-indistinguishable from a live external client; the gate CORRECTLY declines to force-kill it (un-aging would over-kill live clients = regression). A REAL killed-migrate orphan = a dead-PID `statbus-migrate-<pid>` advisory holder (acquireAdvisoryLock, migrate.go:297-298 — foreman verified) + a `statbus-migrate-sql` statistical_* subprocess (migrate.go:303). So the mechanic's relax-to-diagnostic is VACUOUS (watches a non-event) AND un-aging the gate is a regression — BOTH dropped. Foreman reverted the held relax-diff to original. FIX (assigned architect): re-design to the realistic orphan — dead-PID statbus-migrate-<deadpid> advisory holder + statbus-migrate-sql subprocess; assert recovery cleans BOTH (Phase 2 PID-probe kills the holder → Phase 1 sweeps the subprocess); keep install-completes + health. Complements stage-d (empty-app holder). The REAL bounded gap the architect found (a tagged dead-PID holder is counted by neither checkSessionsClean branch → bounded recovery delay) is FILED SEPARATELY as STATBUS-055 (post-RC, PID-liveness-aware gate detection, NOT age-relaxation). NB: the task's seed-restore/pg_restore-vs-STATBUS-018 line is a SEPARATE cross-linked issue, not part of this verdict.

RE-DESIGN COMMITTED 55d5efa96 (foreman reviewed + ratified the architect's design call). 029 now synthesizes the REALISTIC orphan: an EMPTY-app advisory holder (simulate_advisory_zombie_empty_app, the rune PID-9962 shape — gate-detectable so GREEN on current code) + a statistical_* psql subprocess; asserts recovery cleans BOTH by CAPTURED backend PID (Phase 2 reaps the holder, Phase 1 sweeps the subprocess), avoiding a false-positive on the install's own boot-migrate empty-app holder; keeps step9 + upgrade-service + health assertions; fail-fast if neither wedge engages. DESIGN CALL (foreman-ratified): empty-app holder = green-for-this-RC; the TAGGED `statbus-migrate-<deadpid>` holder (the 055 detection gap) is NOT folded in here — it stays as STATBUS-055's own RED→GREEN. Complements stage-d (holder alone). bash -n clean; helpers verified. NOT yet VM-validated (harness convention — wedge/keepalive timing needs tuning); validated in the comprehensive matrix run once the daemon-startup fix (31db8cec0) confirms green.
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
DONE — 5-install-stage-a-killed-migrate is GREEN as of run 27731940038 (2026-06-18). The task's original premise (a pg_restore/seed-restore root, STATBUS-018) was wrong: the real cause was the VM_EXEC multi-line transport bug (a `printf %q`/newline collapse turned a multi-line if/then into a bash syntax error), fixed in batch 2a (783bb0905). The separate seed-restore-on-populated-DB concern remains tracked under STATBUS-018. Closed during the 2026-06-18 board cleanup.
<!-- SECTION:FINAL_SUMMARY:END -->
