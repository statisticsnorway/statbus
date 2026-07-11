---
id: STATBUS-158
title: >-
  pg-regress-straggler-guard: a killed harness run leaves pg_regress writing in
  the container while the flock frees — refuse loudly + NUL tripwire
status: In Progress
assignee:
  - mechanic
created_date: '2026-07-11 20:57'
updated_date: '2026-07-11 23:42'
labels:
  - testing
  - dev-tooling
  - fail-fast
dependencies: []
references:
  - dev.sh
  - STATBUS-133
  - STATBUS-157
priority: high
ordinal: 159000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
> NORTH STAR: exactly one pg_regress ever writes the shared output directory; a straggler from a dead harness run is refused loudly by the next run, never silently raced.
> STAGE: harness integrity. FOUND: 2026-07-11 — the 303/307 "silent truncation" investigation; the architect caught the mechanism LIVE (two concurrent pg_regress instances, different test DBs, same --outputdir=/statbus/test).
> COMPLEXITY: mechanic-simple; the shape is architect-ruled (below).

THE MECHANISM (conviction-grade, observed live): the dev.sh test-run serialization flock lives on a HOST fd and dies with the host process tree — but pg_regress runs via docker compose exec, spawned by containerd inside the VM, and does NOT inherit that fd. Kill or lose a harness run after pg_regress starts → the flock releases immediately while the container-side pg_regress keeps running and writing. The next invocation acquires the lock legitimately and starts a SECOND pg_regress into the same outputdir. Two writers on one .out: writer B's fopen truncates and writes its head; writer A's next flush lands at its own saved offset; the kernel zero-fills the gap — a sparse NUL hole with correct content on both sides (both writers emit identical deterministic output at different paces). The non-page-aligned hole offsets and the largest-two-files correlation both fit this and NOT the initially-suspected Docker bind-mount story (page-cache loss is 4096-granular; the longest tests have the widest overlap window).

THE RULED GUARD, two parts (architect, 2026-07-11):
(a) ROOT FIX: immediately after acquiring the test-run lock and BEFORE starting pg_regress, check for existing pg_regress/regress-psql processes in the db container (docker compose exec db pgrep -a pg_regress); if found, REFUSE LOUDLY naming the pids and the exact kill command. NO auto-kill — per the no-standing-self-heal rule, recurrence fails loudly with the fix named, never quietly repaired. Same banner shape as the lock's own contention message.
(b) TRIPWIRE: a NUL-byte detector on .out files — an embedded NUL is never legitimate; fail with a distinct "corrupted output" verdict whose message names the real first-check (straggler pg_regress + the pgrep command), and PRESERVE the corrupted file as tmp/corrupted-<test>-<timestamp>.out before any rerun (the original incident's byte schedule was lost to overwriting reruns).

(a) is the fix; (b) catches any OTHER corruption class honestly and keeps the evidence.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 A run started while a container-side pg_regress exists refuses loudly, naming the pids and the exact kill command — no auto-kill, no silent race
- [ ] #2 An embedded NUL in any .out fails with the distinct corrupted-output verdict naming the straggler first-check, and the corrupted file is preserved under tmp/ before any rerun
- [ ] #3 The guard's check + the flock ride the same code path so the loophole cannot silently reopen
<!-- AC:END -->

## Comments

<!-- COMMENTS:BEGIN -->
author: architect (via foreman)
created: 2026-07-11 22:13
---
Execution notes (architect, 2026-07-12, post-ticketing review): (1) the post-lock pgrep check must match BOTH pg_regress AND its regress psql children — a dying pg_regress can leave the psql child still writing, so pgrep for pg_regress alone leaves the loophole half-open. (2) The refuse banner must reuse the test-run lock's existing contention-banner style — one consistent operator voice, same shape as the lock's own contention message.
---

author: architect (via foreman)
created: 2026-07-11 23:42
---
REVIEW VERDICT (architect, 2026-07-12): SHIP AS-BUILT. Conformance: guard placed INSIDE acquire_test_run_lock (re-entrancy verified — child dev.sh invocations pass through via STATBUS_TEST_LOCK_HELD, so a run never blocks on its own pg_regress; only the outermost acquirer checks); tripwire covers both pg_regress invocation sites (the isolated site covers the fast/all loop by construction). The match pattern pgrep -af 'pg_regress|HIDE_TABLEAM' is empirically derived from a live process table: pg_regress redirects its psql child via fork+dup2, so the child's argv never carries the outputdir — path-matching would miss the orphaned-child case; HIDE_TABLEAM is a psql -v var only pg_regress injects, catching both parent and orphan.

FAIL-OPEN RULED ACCEPTABLE, BY DESIGN (record so it reads as designed, not overlooked): the guard's exec rc=1 is ambiguous between pgrep-no-match, db-container-down, and daemon-unreachable — but every such state is either genuinely inert (a down container contains no processes; no straggler can exist in it) or fails THIS run loudly seconds later at its own docker compose exec on the same dependency; the guard never needs to be the fail point for infrastructure the run hard-depends on immediately after. Distinguishing exec-failure reasons would require parsing compose stderr (text-as-classifier, banned per doc-022) or a ps pre-check that can itself transiently fail. The residual — transient exec failure at guard time AND a live straggler AND an imminent collision — is a conjunction of rare events, and the NUL tripwire is the evidence-preserving backstop for exactly that class: two independent layers where the first fails open into the second's detection.

All three legs live-verified by the mechanic (happy path inert; real fake straggler refused pre-pg_regress; real NUL-embedded .out detected + preserved byte-intact). One optional nit folded at commit: on cp failure the tripwire banner reports '(preservation FAILED — original left at <file>)' instead of naming a copy that does not exist.
---
<!-- COMMENTS:END -->
