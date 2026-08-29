---
id: STATBUS-315
title: >-
  user-id-nondeterminism: two full replays disagree on auth.user id allocation
  (2 vs 32) — name the mechanism before the 098 fix erases the signal
status: In Progress
assignee:
  - tester
created_date: '2026-08-28 23:42'
updated_date: '2026-08-29 10:58'
labels:
  - testing
  - migrations
dependencies: []
priority: medium
type: spike
ordinal: 308000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
NORTH STAR: the same input must build the same database. Two full-from-migrations replays on the same machine on the same night allocated different auth.user ids for the same test fixture (098 observed id 2 on the first rebuild, id 32 on the second). That is NONDETERMINISM — a different and potentially worse class than the order-dependence 312/108 exposed, because order-dependence at least yields the same answer for the same path.

WHY THIS TICKET EXISTS SEPARATELY (architect's 314 ruling, verbatim requirement): fixing 098 to be id-deterministic (sequence restart, the house rule) is correct and is happening aboard rc.17 — but that fix ERASES the 2-vs-32 signal. This ticket preserves the question so the symptom fix cannot close it. Do not let this become invisible.

INVESTIGATION (read-only): what advanced the auth.user id sequence differently between the two replays? Candidates to check with bytes, not hypotheses: migrations that create-and-delete users; retry/error paths in migrations that consume sequence values without keeping rows; anything in the replay machinery (create-db, template construction) that inserts users conditionally on environment; whether the killed-then-rerun first rebuild left the sequence in a different position than a clean run. Name the mechanism, then classify: benign (sequence gaps are unspecified behavior nothing may depend on — then the finding is a documented rule that no test or migration may assume absolute ids) or a genuine replay nondeterminism with state consequences beyond ids (then it escalates to the architect for a 314-style classification).

Blocks nothing; rc.17 does not wait on it.

WHAT IS ACHIEVED: the signal survives its own symptom fix, and either a mechanism is named or a rule is recorded.
<!-- SECTION:DESCRIPTION:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
**Context: the ~23:00 UTC suite-kill attribution is CLOSED as non-human** (all three team members accounted for with clean timelines: engineer was the run's owner/victim; mechanic's concurrent attempts were blocked by the test-run lock and he killed only his own wrapper pids; tester was read-only throughout). Cause class: external/environment kill (macOS/docker resource kill, STATBUS-158 family). Consequence for this investigation: the killed-then-rerun leftover state is the leading candidate for what differed between the two replays' sequence positions — the first (killed) rebuild's partial state may have advanced auth.user id allocation differently than the second clean one.

**Tester's mechanism report (2026-08-29): NAMED.** auth.user_id_seq is never reset between rebuilds — test/setup.sql:31-33 resets the enterprise/legal_unit/etc. sequences but not auth's — and the seed-restore path (per-commit statbus-seed:<short> artifact → pg_restore → incremental migrate up; FULL_REPLAY fallback when no artifact) leaves the sequence wherever the restored artifact captured it. Two rebuilds restoring different artifacts, or one taking the fallback, start fixture users at different ids: 2 vs 32. Classification: GENUINE nondeterminism affecting test-output validation — escalated to the architect with three remedy options: (1) setup.sql resets auth.user_id_seq like its siblings (with the foreman's caution: must be setval-to-max, not restart-at-1, to avoid colliding with seed-created users); (2) seed restoration guarantees sequence state; (3) never-assert-ids as a standing test convention. Architect ruling pending on which land tonight.
<!-- SECTION:NOTES:END -->

## Comments

<!-- COMMENTS:BEGIN -->
author: engineer
created: 2026-08-29 10:58
---
**Both items built and frozen. The mechanism was measured, not inferred — and my first draft of it was wrong.**

**WHAT ACTUALLY CAUSES THE DRIFT.** Rollback restores ROWS, not SEQUENCES. `nextval()` is non-transactional, so a value consumed by an INSERT that later rolls back is burned and never returned. Most test files open `BEGIN;` **before** `\i test/setup.sql` (verified across test/sql/ — it is the dominant pattern), so the three fixture users are rolled back when the file ends: the rows vanish, the burned ids do not come back. Shared tests run sequentially on one database, so each subsequent file's setup inserts its users higher up. **The ids a test sees depend on which tests ran before it** — which is exactly why a targeted run and a full replay disagreed.

**MEASURED, with a temporary probe test that printed the fixture ids (created, used, deleted):**

| run | admin | regular | restricted |
|---|---|---|---|
| alone, derivation disabled | 1 | 2 | 3 |
| after 009 + 013 + 018, derivation disabled | **19** | **20** | **21** |
| either order, derivation enabled | 1 | 2 | 3 |

That is the red and the green of this unit. The RED half required temporarily disabling only the new statement in `test/setup.sql`; it was restored byte-identically (`69bd1e0fcf2a465f` in and out) via `cp`, behind a guard that refuses to mutate a shared fixture while any migration/seed/test command is live.

**A PREMISE I HAD TO RETRACT.** My first version of the comment said the ids climb because "some test deletes the users and commits". The measurement disproves that — no deletion is involved. The cause is the ordinary rolled-back setup, repeated. I rewrote the comment to the measured mechanism rather than leaving a plausible story in the file.

**AND THE QUESTION THAT SHOULD BE ANSWERED IN THE FILE, NOT ASSUMED:** is the fix more transaction discipline? **No.** The tests already run in a transaction and already roll back — that is the very thing that burns the ids. The sequence sits outside transactional control by design, so wrapping the test more tightly cannot help. Both artifacts now say this explicitly, because it is the first thing a reader will propose.

**ITEM 1 — `test/setup.sql`,** placed immediately before the three `user_create` calls:

    SELECT setval(
        pg_get_serial_sequence('auth."user"', 'id'),
        GREATEST(COALESCE((SELECT max(id) FROM auth."user"), 0), 1),
        EXISTS (SELECT 1 FROM auth."user")
    );

`pg_get_serial_sequence` rather than a hardcoded name, so a rename cannot silently no-op it. `is_called` from `EXISTS` so an empty table yields next = 1 rather than skipping id 1. Derivation rather than `RESTART` because deriving from `max(id)` discards the burn history — two databases holding the same users agree on ids regardless of path — whereas `RESTART WITH 1` is only correct on an empty table (which is precisely why the unit sequences above it may use it and this one may not). The honest bound and the REMOVE-WHEN-normalize-every-sequence-after-restore-LANDS note are both recorded at the line, as required.

**ITEM 2 — `.claude/rules/testing.md`,** new section "Rollback restores rows, not sequences — and what that means for ids": the mechanism, the measured table above, the explicit "more transaction discipline is not the fix", then the preference order (natural key -> same-replay comparison -> count) with 329 and 098 as the worked examples. It does NOT issue a blanket ban: with the derivation in place the fixture users are dependably 1, 2, 3 and a test may rely on that. What is not promised is permanence — those numbers derive from the seed's user set, so a migration seeding or removing users moves all of them. The rule covers that residual risk; the setval removes the run-order dependence.

**BLAST RADIUS: ZERO.** 69 expected files mention the fixture emails and 27 reference a user-id column, but nothing changed. Wave 1 (009, 013, 018, 098, 323, 329) and wave 2 (adding 102 and an import test that prints user ids) both ran ALL GREEN with no diffs and nothing blessed. That matches the mechanism: in a fresh clone the setval is a no-op (empty table, sequence already at next = 1), and on a re-run `ON CONFLICT DO UPDATE` keeps the existing ids. The line only changes outcomes in the case that was already broken. **No baselines were re-blessed, so the quieting did not silently re-bless anything.**

**FROZEN — 2 files:** `test/setup.sql` (+52, one functional statement), `.claude/rules/testing.md` (+55, documentation only).

Not mine and dirty in the tree from another agent's work — do not stage with this unit: `test/expected/108_test_code_gen.out`, `test/expected/303_*` and its three explain baselines, `test/expected/performance/109_hierarchy_functions.perf`, plus the untracked 20260829103700 migration pair and test 126.
---
<!-- COMMENTS:END -->
