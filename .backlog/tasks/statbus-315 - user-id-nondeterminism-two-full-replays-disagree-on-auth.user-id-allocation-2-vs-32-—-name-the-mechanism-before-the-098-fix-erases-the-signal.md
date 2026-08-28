---
id: STATBUS-315
title: >-
  user-id-nondeterminism: two full replays disagree on auth.user id allocation
  (2 vs 32) — name the mechanism before the 098 fix erases the signal
status: In Progress
assignee:
  - tester
created_date: '2026-08-28 23:42'
updated_date: '2026-08-28 23:46'
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
