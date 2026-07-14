---
id: STATBUS-175
title: >-
  pg-regress-echo-flake: intermittent loss of `\i` include echo makes echoing
  tests nondeterministic
status: To Do
assignee: []
created_date: '2026-07-13 13:20'
updated_date: '2026-07-14 10:47'
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
- [ ] #1 Reproduce the intermittent include-echo drop deterministically (or characterise the trigger: concurrency, \o flush timing, psql version) with a minimal repro
- [ ] #2 Decide the fix: either root-cause the echo drop in the harness/setup.sql, or adopt the 403 pattern (suppress shared-include output) as the standard for tests that \i getting-started.sql + definitions
- [ ] #3 Audit existing echoing tests (401, others) for exposure; apply the chosen fix so no committed expected depends on include-echo luck
<!-- AC:END -->

## Comments

<!-- COMMENTS:BEGIN -->
author: foreman
created: 2026-07-14 10:47
---
POSSIBLY-RELATED OBSERVATION (2026-07-14): during the engineer's STATBUS-178 fast-suite run, test 314_consecutive_demo_loads (the slowest test, ~40-59s) failed with OUTPUT-FILE CORRUPTION — a line truncated mid-token plus whitespace explosion in the results file; the test passed clean solo immediately after, and my full-suite counter-run the same hour was 86/86 green (314 ok in 39s). One occurrence, not reproduced. Same family as this ticket's \i-echo nondeterminism? Both are pg_regress OUTPUT-stream integrity flakes on long/slow tests rather than SQL behavior differences. No dismissal — recording so the pattern accumulates; if a third distinct corruption shape appears, this ticket's investigation should cover the output-capture path (psql → results file I/O), not just the echo semantics.
---
<!-- COMMENTS:END -->
