---
id: STATBUS-175
title: >-
  pg-regress-echo-flake: intermittent loss of `\i` include echo makes echoing
  tests nondeterministic
status: In Progress
assignee:
  - '@mechanic'
created_date: '2026-07-13 13:20'
updated_date: '2026-07-14 23:33'
labels:
  - testing
  - not-install-upgrade
dependencies: []
references:
  - test/sql/403_cross_border_power_group.sql
  - test/setup.sql
  - test/sql/401_import_jobs_for_brreg_selection.sql
priority: low
ordinal: 176000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
NORTH STAR: a pg_regress test's expected output never depends on luck.

CONCRETE OBSERVATION (2026-07-13, while building test/sql/403_cross_border_power_group.sql): the same test file, same command (`./dev.sh test 403_cross_border_power_group`), run three times back-to-back on the same DB, produced TWO different result-file lengths:
- runs b6wfa8a41 and bal7nbzfy: 569 lines — the `\i`-included setup files (getting-started.sql + the BRREG import-definition SQL + seed) were ECHOED in full (this is the normal, expected behaviour, matching committed test 401).
- run bamd270dk: 296 lines — those same includes were NOT echoed. The test still COMPLETED with identical final query results (PG0001, 23 members, exit 0); only the include echo was absent.

So `\set ECHO all` (set at test/setup.sql:133) intermittently fails to echo subsequent `\i` file contents. It is not truncation (the run reached PHASE 4 cleanup) and not a query-result difference — purely whether the included SQL text is echoed.

WHY IT MATTERS: every test that echoes its includes (e.g. test/sql/401_import_jobs_for_brreg_selection.sql, which commits the full echoed hovedenhet/underenhet definition SQL in its expected) is susceptible to a spurious diff-failure when this drop occurs. Per the project's "there are NO flaky tests" principle, this latent harness nondeterminism should be root-caused, not tolerated.

WORKAROUND ALREADY IN PLACE (403 only): 403 wraps its shared includes in `\o /dev/null` + `\set ECHO none` ... `\o` + `\set ECHO all`, so the includes contribute nothing to its expected — deterministic and decoupled from getting-started.sql churn. That pattern is a candidate fix to generalise, but the underlying intermittent echo drop is unexplained and worth understanding first.

SUSPECTS to investigate: interaction of test/setup.sql's `\o /dev/null` (line 3) + `\o` reset (line 132) + `\set ECHO all` (line 133) with pg_regress's psql invocation; possible buffering/flush timing on the `\o` redirect; possible harness-level concurrency (dev.sh has straggler-pg_regress guards for a reason).
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Reproduce the intermittent include-echo drop deterministically (or characterise the trigger: concurrency, \o flush timing, psql version) with a minimal repro
- [x] #2 Decide the fix: either root-cause the echo drop in the harness/setup.sql, or adopt the 403 pattern (suppress shared-include output) as the standard for tests that \i getting-started.sql + definitions
- [ ] #3 Audit existing echoing tests (401, others) for exposure; apply the chosen fix so no committed expected depends on include-echo luck
<!-- AC:END -->

## Comments

<!-- COMMENTS:BEGIN -->
author: foreman
created: 2026-07-14 10:47
---
POSSIBLY-RELATED OBSERVATION (2026-07-14): during the engineer's STATBUS-178 fast-suite run, test 314_consecutive_demo_loads (the slowest test, ~40-59s) failed with OUTPUT-FILE CORRUPTION — a line truncated mid-token plus whitespace explosion in the results file; the test passed clean solo immediately after, and my full-suite counter-run the same hour was 86/86 green (314 ok in 39s). One occurrence, not reproduced. Same family as this ticket's \i-echo nondeterminism? Both are pg_regress OUTPUT-stream integrity flakes on long/slow tests rather than SQL behavior differences. No dismissal — recording so the pattern accumulates; if a third distinct corruption shape appears, this ticket's investigation should cover the output-capture path (psql → results file I/O), not just the echo semantics.
---

author: foreman
created: 2026-07-14 22:26
---
AC#1 INVESTIGATION COMPLETE (mechanic, 2026-07-14/15 night): NO REPRO in 38 dev.sh test invocations across 3 conditions — plain back-to-back 0/20, 'concurrent' 0/6, db-container CPU load 0/12; zero output-stream corruption observed. KEY HARNESS FACT: dev.sh:587-656 acquire_test_run_lock is a GLOBAL flock on tmp/.test-run.lock serializing ALL test/create-db invocations process-wide — empirically confirmed (second concurrent invocation BLOCKED until the first released) — which RULES OUT two-intentional-invocations as the concurrency vector; the only surviving concurrency vector is the STATBUS-158 straggler/orphan-pg_regress class (deliberately NOT forced — out of proportion for a low-priority ticket; revisit only if a third corruption sighting lands, per comment #1's accumulation rule). Surviving mechanism suspect, UNCONFIRMED: a psql-internal stdout-buffering quirk at the test/setup.sql:132-133 \o-reset→ECHO-all boundary (ECHO=all documentedly writes to psql stdout independent of \o, so any interaction is un-documented C-level timing). 403's inline comment already documents the drop as known-when-built; 401 remains EXPOSED (no suppression wrapping). Container psql 18.4. Artifacts: tmp/175-echo-flake-loop.sh + tmp/175-echo-flake-concurrent.sh (permanent drivers), tmp/175-echo-flake-runs.log (61-line ledger), tmp/175-run-*.dev-sh.log ×44. Portability trap recorded: bash collapses $'\x00' in argv and local grep is ugrep (empty pattern + -U matches everything) — NUL checks must use perl -0777.

AC#2 DECIDED (foreman): ADOPT THE 403 SUPPRESSION PATTERN as the standard for tests that \i shared setup/definition files. Grounds: the drop is real (observed 2026-07-13) but rare and timing-sensitive (0/38 under directed stress); the harness serializes honest invocations by design; the surviving suspect is psql-internal and not ours to fix; and the 403 pattern independently decouples committed expected files from getting-started.sql churn — a robustness win even if the flake never fires again. Root-causing psql's C-level buffering is out of proportion. AC#3 (audit + apply) dispatched to the mechanic.
---

author: foreman
created: 2026-07-14 22:30
---
AC#3 AUDIT RESULT + SCOPE RULING (2026-07-14/15 night): the mechanic's read-only audit found 61 exposed tests (37 via the Norway getting-started chain, 24 via demo; verified genuine \i-echo in expected, not coincidental substrings; list at tmp/175-ac3-audit-exposed-list.txt) — essentially the whole 1xx-4xx suite, not the handful the dispatch assumed. FOREMAN SCOPE RULING: full sweep stands (the North Star tolerates no committed expected depending on echo luck) but ships in BATCHES of ~15, each independently reviewed+committed — batch 1 = 401 + fast-suite members + 4xx series, then numeric order. Per-file PURPOSE GUARD adopted from the mechanic's flag: any test whose stated purpose involves the seed/definition content itself is EXCLUDED from the blanket wrap and gets an individual ruling; likewise any regenerated expected whose diff is not purely removal-of-echo. Regeneration is serialized by the dev.sh global test flock — batches bound each run-block.
---

author: foreman
created: 2026-07-14 22:47
---
INFRA EVENT DURING BATCH 1 (2026-07-14 ~22:06-22:44 UTC, local dev db): TWO postgres crash-recovery cycles inside the mechanic's own heavy-run windows (investigation load variant; the long 401 regeneration). Foreman pulled the db logs: no explicit OOM lines, but the shape (backend silently killed → postmaster crash recovery → container never restarted) is the macOS Docker memory-pressure signature under heavy import load — most probable cause is the runs' own resource pressure, not an external actor. The killed 401 run died mid dev.sh DROP DATABASE (22:43:53 'connection to client lost') and orphaned a pg_regress+psql straggler — a NATURAL occurrence of exactly the straggler/orphan vector this ticket's AC#1 investigation deliberately left unforced; no echo-drop or output corruption was observed from it (the run died outright), recorded here per the accumulation rule. Mechanic cleaned up via dev.sh's own documented remediation (stragglers killed, isolated test DB dropped, recovery confirmed complete). Guard rule for the rest of the sweep: plain serialized runs only; a THIRD recovery cycle during a plain run is stop-and-report (falsifies the memory-pressure read → check Docker Desktop memory allocation).
---

author: foreman
created: 2026-07-14 23:33
---
BATCH-1 SPLIT AFTER THIRD RECOVERY CYCLE (2026-07-15 night): the stop-rule fired — a third dev-db crash-recovery cycle landed ~30s after the mechanic's straggler kill -9, 2-for-2 timing across incidents, which falsifies the simple memory-pressure read (a killed CLIENT psql cannot crash-recover the postmaster; only a backend death can). Foreman's own log check found postgres's root-event evidence UNREACHABLE (no 'terminated by signal' line in the container's entire docker-log history; the in-container collector file is empty) — escalated as STATBUS-188 (dev-db-crash-cycles) with the runner-timeout chain-starter (401's ~28-min regeneration exceeds the background-runner budget, manufacturing stragglers by construction) in scope. RESOLUTION FOR THIS TICKET: batch 1a = the 18 completed files (all regenerated + diff-reviewed removal-only), freezing now for foreman review+commit; 401 is DEFERRED to after STATBUS-188's infra answers — not retried in a timeout-bounded runner. Standing order to the mechanic: no more kill -9 in the db container (the remediation itself is under investigation, 188 AC#3); stragglers get reported and left.
---
<!-- COMMENTS:END -->
