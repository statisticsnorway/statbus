---
id: STATBUS-305
title: >-
  exhaust-arm-terminal: when the db never returns, the daemon parks and refuses
  to restore blind — the scenario asserts a terminal the doctrine forbids
status: In Progress
assignee:
  - '@architect'
created_date: '2026-08-28 18:54'
labels:
  - upgrade
  - install-recovery
  - testing
dependencies: []
priority: high
type: task
ordinal: 298000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
NORTH STAR: decide what the CORRECT terminal state is when the database never comes back — and make the scenario assert that, or build the fallback it assumed. This is the last unattributed red in the campaign; its ruling decides rc.16's promotion.

THE FINDING (rc.16 fleet run 33190460349, transient-db-backoff, mechanic's journal triage — 299 CONFIRMED WORKING first: zero SIGABRT/SIGSEGV/watchdog lines, the bounded sub-attempts logging exactly as designed, daemon alive through the whole 11-minute window): the scenario's EXHAUST arm deliberately never un-pauses the db — its premise is "the db never returns, so the backoff exhausts and the daemon rolls back anyway (data-safe)". The daemon exhausts the budget on schedule, then hits the verify-before-restore doctrine: 'recoveryRollback: upgrade 2 is PARKED (park state UNKNOWN — the read failed (conn closed); refusing to restore on an unverified row) — refusing the automatic rollback'. The row stays parked, the unit alive-idle, the connect loop retrying forever with 299's heartbeat attesting progress. The arm's asserted terminal — rolled_back within 600s — is STRUCTURALLY UNREACHABLE: exhausting the budget and verifying state both depend on the same unavailable resource.

THE QUESTION (architect rules): (a) THE SCENARIO IS STALE — parking is the CORRECT terminal for db-never-returns. Verify-before-restore is the never-destroy-state-under-uncertainty doctrine (the 039/111/159 family); restoring a backup over a database you cannot read is the data-corruption pathway; the designed answer to a permanently-dead db is alive-idle + parked + a human. If so, the fix is the ARM's assertion: expected terminal becomes parked + alive-idle + bounded restarts + the connect loop demonstrably still trying — and the arc then asserts the DOCTRINE rather than contradicting it. (b) A MISSING FALLBACK — a forced, local-only rollback once ALL budgets exhaust and verification is impossible was always intended and does not exist. That is a product build with real data-safety stakes and would need its own careful design (what makes a forced restore safe when nothing can be verified?). (c) Something sharper than either.

EVIDENCE STATUS: not a 299 regression (proven working in the same journal); not a 300-class harness impatience (the failing assertion already retries for its full 600s budget — the db was honestly down the entire time, by the arm's own design). The finding is reproducible by construction: this arm reds every run until the ruling lands.

SEQUENCING: rc.16 is otherwise 36/36. If the ruling is (a), the fix is harness-side (the arm's assertions), the scenario greens on the next run, and rc.16's code is promotable as-is with the arc fix landing on master. If (b), there is a real missing product path and the promotion decision needs the King.

WHAT IS ACHIEVED: the one scenario that has found a bug per layer all campaign either asserts the doctrine correctly or names the fallback the product still owes — and the fleet's verdict becomes fully attributable either way.
<!-- SECTION:DESCRIPTION:END -->
