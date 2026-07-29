---
id: STATBUS-175
title: >-
  pg-regress-echo-flake: intermittent loss of `\i` include echo makes echoing
  tests nondeterministic
status: In Progress
assignee:
  - '@mechanic'
created_date: '2026-07-13 13:20'
updated_date: '2026-07-29 15:59'
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

> WHERE THIS STANDS (2026-07-27): ROOT CAUSE NAMED AND ACCEPTED (comment #7; the King: 'meets my standard'). There was no flake. The three 2026-07-13 runs executed DIFFERENT BYTES of the 403 test file — it was under construction, and the suppression wrap being authored between runs is exactly what removed the include echo. psql was deterministic throughout. AC#1 done. AC#2 stands on its independent ground: suppressing shared-include echo decouples committed expected files from include churn. Batch 1a shipped (16 tests converted). REMAINING = AC#3's last three (401, 402, 500), deferred behind STATBUS-188 (dev-DB crash cycles), plus one corollary riding the sweep: reword 403's inline comment at :49-50, which still calls the drop a harness flake.

THE 2026-07-13 OBSERVATION, RESOLVED: the same command run three times "back-to-back" gave 569-, 569-, and 296-line outputs with identical query results. The cause was not psql. The test file itself changed between runs: the 296-line run executed a draft already carrying the `\o /dev/null` + `\set ECHO none` wrap around its includes; the 569-line runs executed pre-wrap drafts. Identical results with missing echo is that edit's exact signature — the wrap changes what is echoed, never what executes. Proof in comment #7: 44/44 fixed-byte runs identical; the two output shapes map one-to-one onto the two file variants; the wrap was committed the same afternoon (f536b38e2) with a comment authored in response to the observation.

WHY THE SWEEP CONTINUES ANYWAY: no committed expected file should depend on the text of shared includes. The 403 suppression pattern removes that dependence — a robustness win independent of the resolved observation.

LESSON, recorded for the next investigator: when variance is observed during active file construction, the file's own bytes are the first suspect input. "Same test file" must be proven, not assumed.
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

author: foreman
created: 2026-07-23 18:37
---
KING RULING (2026-07-23, pre-cut review): the 'psql intermittently ignores the echo setting' characterization is REFUTED AS STATED — 'PSQL, when it runs, is always deterministic. Dig deeper. Don't assume.' AC#1 UNCHECKED: what was recorded as a characterization was an observation of variance, not a root cause. The correct frame: identical psql behavior requires identical inputs, so the three 403 runs (two 569-line outputs with include text, one 296-line without, identical query results) MUST have differed in some input — candidate spaces for the real dig: the \o/ECHO state machine in test/setup.sql (it suppresses via \o and restores at :133-135 — did one run take a different path to/through it?), the dev.sh runner's psql invocation shape, the cloned-DB/template state at run time, a CONCURRENT run colliding (the doctrine's most common real cause), or differing include-file bytes at read time. Root-cause hunt routed to the architect with the three run logs as evidence; the 403 suppress-pattern fix (AC#2) remains valid regardless — it removes the output's dependence on whatever the varying input is — but the ticket does not close on 'characterised' until the varying input is NAMED and proven.
---

author: architect
created: 2026-07-23 18:41
---
ROOT CAUSE NAMED (architect, 2026-07-23, on the King's refutation — he was right, and the dig proves it): THE VARYING INPUT WAS THE TEST FILE'S OWN BYTES. The three 'back-to-back' runs did not run the same 403_cross_border_power_group.sql — the file was under ACTIVE CONSTRUCTION that afternoon, and the edit being authored between runs was precisely the `\o /dev/null` + `\set ECHO none` suppression wrap around the includes. The 296-line run executed a draft CARRYING the wrap; the 569-line runs executed pre-wrap drafts. Identical query results with absent echo is exactly that edit's signature: the wrap changes what is ECHOED, never what EXECUTES. psql behaved deterministically in all three runs. 'Same test file' was the unproven premise.

THE PROOF (convergent, each leg checkable):
(a) DETERMINISM UNDER FIXED BYTES: the mechanic's ledger (tmp/175-echo-flake-runs.log) shows 44/44 runs of the byte-stable noworkaround file producing 574 lines EVERY time — zero variance across plain/concurrent/CPU-load. A timing-sensitive echo drop cannot hide from 44 fixed-input runs; a file-under-edit explains 3/3.
(b) THE TWO OBSERVED SHAPES MAP ONTO THE TWO KNOWN FILE VARIANTS: committed expected (WITH wrap) = 284 lines ↔ the 296-line run (draft drift of ~12 lines); the noworkaround variant (WITHOUT wrap) = 574 lines ↔ the 569-line runs (~5 lines drift). Two output shapes, two file variants, one-to-one — no third mechanism required.
(c) THE WRAP DEMONSTRABLY EXISTED THAT SAME DAY: f536b38e2 (2026-07-13 15:15:56, the test's FIRST commit) carries the wrap at :52-53 with an inline comment authored IN RESPONSE to the observation — the edit and the three runs interleaved in the same working session by the record's own testimony.
(d) NO OTHER INPUT DIMENSION EVER SHOWED VARIANCE: 0/38 directed-stress runs (comment #2), and the global flock rules out honest concurrent invocations.
FALSIFIABILITY: if any of the three original run logs (b6wfa8a41/bal7nbzfy/bamd270dk — searched, not recoverable) ever surfaces, the 296-run's echoed prologue will show the wrap lines themselves (ECHO all echoes the test's own prologue up to `\set ECHO none`); the 569-runs' prologues will lack them.

COROLLARY FIXES: (1) 403's inline comment at :49-50 immortalizes the misreading ('the \i echo has been observed to intermittently drop under the harness') — reword to the true cause (the observation was the file's own in-flight edit); the suppression itself STAYS on its independent, always-valid ground: decoupling committed expected files from shared-include churn (AC#2's decision is unchanged, now with an honest rationale). (2) The AC#3 sweep continues unchanged — same fix, honest reason.

WHAT THIS DOES NOT EXPLAIN, kept honestly separate: the 314 output corruption (comment #1: mid-token truncation + whitespace explosion) is a DIFFERENT class — capture-path integrity, not echo semantics — and the accumulation rule for it stands. SIDE NOTE, unresolved-low: the ledger's per-run 'NUL BYTE DETECTED' lines are suspect — comment #2 itself records the local-grep trap (ugrep + empty pattern matches everything) and the 'preserved' artifacts were not in fact preserved to tmp/; if a NUL check ever matters again, use perl -0777 per the recorded trap.

AC#1 disposition: the varying input is NAMED (the test file's own bytes mid-construction) and proven by (a)-(d) — foreman checks AC#1 if the King accepts this as the standard met.
---

author: foreman
created: 2026-07-25 18:37
---
KING ACCEPTED the root cause (2026-07-25): 'meets my standard.' AC#1 checked — the varying input NAMED and proven (the test file's own bytes mid-edit; psql deterministic throughout; 44/44 fixed-byte runs zero-variance). WHAT REMAINS on this ticket (the King asked): AC#3's sweep tail only — (a) the 403 inline comment reword (one line, removes the immortalized misreading); (b) the three deferred conversions 401/402/500, blocked on STATBUS-188 (dev-db crash cycles) per comment #5; (c) the remaining batches of the 61-test exposure sweep (batch 1a's ~18 shipped; ~40 remain, batched ≤≈15 with per-file purpose guard per the comment-#3 scope ruling). All mechanic-lane, serialized, none release-gating.
---

author: foreman
created: 2026-07-29 11:05
---
PLAN-TO-FINISH (foreman, 2026-07-29 — King directive: drive this ticket to Done without further King/foreman attention). ASSIGNEE: mechanic (stays — the sweep was scope-ruled mechanic-lane in comment #3; no design content remains). STANDING ORDER: batches 2..N run back-to-back — mechanic builds a batch (≤15, numeric order, per-file purpose guard), reports, foreman line-reviews + commits, mechanic proceeds to the next batch immediately; purpose-guard exclusions get individual foreman rulings without stalling the rest of the batch. Batch 2 dispatched today. All stop-rules stand (plain serialized runs; no kill -9 in the db container; stragglers/crash-cycles reported and left). FINISH LINE for THIS ticket: every test on the 61-test exposure list (tmp/175-ac3-audit-exposed-list.txt) is either converted or individually ruled excluded — EXCEPT 401, 402, 500, whose conversions TRANSFER to STATBUS-188 as a finalization step there (401's ~28-min regeneration is the very workload 188 investigates; recorded on 188 same-turn; the King is visiting 188 and can override the transfer). When the sweep-minus-three is green and committed, AC#3 checks with the carve-out noted and 175 closes Done. The 403 comment-reword corollary is already done (verified at test/sql/403_cross_border_power_group.sql:45-49).
---

author: foreman
created: 2026-07-29 11:17
---
BATCH 2 REVIEW (foreman, 2026-07-29): HELD for one systemic fix; structure otherwise clean (exactly 30 files; .sql wraps additions-only — 303's one deleted line is a blank line inside the wrap span, accepted; .out numstats match the wrap shape: 7 added/≈23 removed for the 13 singles, 375 removed for 302/303's BRREG-def echo; zero purpose-guard exclusions, verified plausible). SYSTEMIC FINDING: the wrap comment — copied verbatim from batch-1a's committed style — still claims 'the \i echo has been observed to intermittently drop under the harness', the exact characterization REFUTED by the King (comment #6) and replaced by the proven root cause (comment #7). Only 403 itself was ever re-worded; batch 1a (16 committed pairs: 003, 103-107, 109-113, 117-120, 400) carries the stale claim in .sql AND .out (the comment echoes into expected output). Grep-verified: 31 sql + 31 expected files total (15 frozen batch-2 + 16 committed batch-1a). RESOLUTION: batch 2 returns to the mechanic for a synchronized byte-identical reword in both pair members (canonical honest texts issued, modeled on 403:45-49), verified by mechanical sql↔out byte-compare on all pairs + spot-runs of 124/302/303 (one per shape class); then a BATCH-1A REMEDIATION unit (same fix in the 16 committed pairs) lands BEFORE batch 3. The sweep's canonical comment text is now pinned in this comment's dispatch — batches 3+ use it directly.
---

author: foreman
created: 2026-07-29 15:54
---
BATCH 2 LANDED 335fc86ee (foreman, 2026-07-29): 15 tests (124, 200-204, 300-308), 30 files, 256 insertions / 1048 deletions of echoed include text. Held-fix verified before commit BY INDEPENDENT RE-CHECK: my own sql↔out byte-compare across all wrap blocks in all 15 pairs (byte-identical, including 302's two blocks), grep zero on the refuted wording, mechanic's three spot-runs green (124/302/303 — one per wrap shape). One review-harness note for the record: my first byte-compare run false-reported 18 mismatches because local grep is ugrep and the block text starts with '--' — exactly the portability trap comment #2 recorded; fixed with the '--' option terminator. Mechanic's infra note logged: the 12:06 network outage broke DNS for local.statbus.org and dev.sh's template-check misreported it as 'template not found' (stderr swallowed) — a harness-diagnostics gap worth a look if it recurs; no db mutation occurred. SWEEP POSITION: 31 of the 58 in-scope tests converted (batch 1a's 16 + 403 + batch 2's 15 minus overlap — batch 1a 16, batch 2 15, 403 pre-existing). REMAINING: batch-1a REWORD remediation (in build now — mechanic already has 003/103/104 in the tree), then ~12 remaining conversions in batch 3, then AC#3 checks with the 401/402/500 carve-out (riding 188).
---

author: foreman
created: 2026-07-29 15:59
---
BATCH-1A REMEDIATION LANDED 8d2205d0f (foreman, 2026-07-29): the 16 July-14 pairs (003, 103-107, 109-113, 117-120, 400) now carry the canonical honest wording — 130 insertions / 130 deletions, perfectly symmetric (4/4 per singular file, 5/5 for 400's plural). Independently re-verified before commit: sql↔out byte-identical on all 16 pairs, grep zero (with the '--' terminator), mechanic's spot-runs green across all three chain shapes (104 Norway / 111 demo / 400 multi-include). With this, the refuted flake claim is grep-zero across the ENTIRE repo — the misreading is fully retired from code, comments, and expected files. ARITHMETIC CORRECTION to comment #11: remaining conversions = 27, not ~12 (61 exposed − 16 batch-1a − 15 batch-2 − 3 transferred to 188 = 27; 403 was never on the exposure list). Mechanic proceeds to batch 3 (next ≤15, numeric order, canonical wording from the start) per the standing order. Note for the record: test/install-recovery/README.md is modified in the tree by the ARCHITECT'S in-flight 196 step-3 cross-link work — attributed, deliberately excluded from this commit.
---
<!-- COMMENTS:END -->
