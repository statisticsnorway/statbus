---
id: STATBUS-315
title: >-
  user-id-nondeterminism: two full replays disagree on auth.user id allocation
  (2 vs 32) — name the mechanism before the 098 fix erases the signal
status: To Do
assignee:
  - tester
created_date: '2026-08-28 23:42'
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
