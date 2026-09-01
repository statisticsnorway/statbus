---
id: STATBUS-127
title: >-
  king-decision-queue: the open decisions awaiting the King, with context —
  resolved one by one
status: Done
assignee: []
created_date: '2026-07-02 19:44'
updated_date: '2026-07-03 19:04'
labels:
  - decisions
  - coordination
dependencies: []
priority: high
ordinal: 128000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
The single durable list of decisions currently parked on the King, each with enough context to rule on. The foreman updates this entry as decisions are made (answer recorded per item, item checked off); teammates do NOT act on any item until its answer is recorded here or on the owning ticket.

## D1 — Read-only-window fix nod (STATBUS-110, doc-023) — HIGHEST LEVERAGE
The committed read-only upgrade window deadlocks every upgrade's health check: PostgREST's notification listener demands a read-write session, readiness requires that listener, and read-only lifts only after completion — a proven circular deadlock (VM arcs + local repro). FIX, empirically pre-verified: one migration line `ALTER ROLE authenticator SET default_transaction_read_only = off` (role setting outranks the database window). Verified: readiness green in 5s under the window AND a non-exempt superuser still write-blocked — the accident-guard survives for every other role; REST's external writes stay blocked by the maintenance gate; direct-DB integrator roles stay frozen. YES releases: the 1-line migration → VM arc re-run → closes 110's regression + 118's done-gate + gives 109 its behavioral oracle. Owning ticket: STATBUS-110 comments 6-8.

## D2 — Install/upgrade backlog consolidation ratification
tmp/plans/install-upgrade-consolidation.md: 6 root-cause clusters; ~19 closes-as-subsumed + 1 merge + 3 verify-closes + 11 re-labels; board shrinks ~40 → ~10 (6 cores + 4 keeps). Every close carries a quoted evidence line. Also corrects the "zero product bugs" tag: 4 real shipped-code defects identified (092/055/018/027-product). Options: ratify all / ratify-but-close-only-as-cores-land / cluster-by-cluster walkthrough.

## D3 — Recovery-escalation ratification (STATBUS-046, doc-021) — now with the per-step walk
The park-instead-of-loop-forever design. Your earlier bounce (which steps does the crash budget cover?) is answered: doc-021 now walks all 44 pipeline operations with file:line, per-step failure classes, and the explicit budget boundary (first counted step = the flag write; last = completed-write + flag removal; phases 0 and 5 outside). FOUR asks: allowance values (tunable at build), crash budget = 3 + same-step-twice→park, the two park columns, the budget boundary as stated.

## D4 — Seed-incremental enable-flip timing (STATBUS-116)
The drift fix is shipped; the TRUE cross-build proof can only re-arm against a seed published post-fix once real migrations accumulate (can't be forced — by construction). Fork: (a) WAIT for that confirming run (conservative; the ~2min→seconds CI build win arrives with the next migration-bearing release cycle) vs (b) FLIP EARLIER on the local invariant test + the certified single-delta proof, with the multi-delta run as a post-enable confirming gate.

## D5 — CrowdSec allowlist on niue (STATBUS-069 territory)
niue's intrusion-prevention blocklist contains 1,027 GitHub/Azure runner IPs → intermittent TCP timeouts for ANY CI→niue SSH (notify + potentially deploys). Note: zero active local decisions suggests a community blocklist feed — recurs regardless of our sshdo fix. Options: (a) allowlist GitHub Actions' published ranges in CrowdSec (durable; modestly widens SSH exposure, mitigated by the per-account sshdo command allowlist), (b) tolerate intermittent timeouts. Server write — needs explicit approval either way.

## D6 — The --recreate durability fix go-ahead (STATBUS-092)
Verified near-deterministic bug: --recreate intent rides a second notification that always loses to the scheduling commit's own notification → the operator's recreate silently runs as a normal upgrade. Design (endorsed): durable `recreate` column on public.upgrade, set at scheduling, read atomically at claim; DELETE the volatile in-memory flag + the racing notification (clean break). Cost: one schema migration on public.upgrade + paired doc/db + types regen, reviewed like every migration. Deterministic DB-backed test proves the flow.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 D1 read-only fix nod — answered + recorded
- [x] #2 D2 consolidation ratification — answered + recorded
- [x] #3 D3 recovery-escalation (046) ratification — answered + recorded
- [x] #4 D4 seed enable-flip timing — answered + recorded
- [x] #5 D5 CrowdSec allowlist — answered + recorded
- [x] #6 D6 recreate-fix go-ahead — answered + recorded
<!-- AC:END -->

## Comments

<!-- COMMENTS:BEGIN -->
author: foreman
created: 2026-07-03 10:34
---
KING'S FIRST INTERVIEW PASS (2026-07-02 evening): D4 ANSWERED = FLIP EARLY — 'why would we wait? we wish to verify that it works, so we need to use it to exercise the code' — the wait-option was a false choice; enable + let real use exercise it, multi-delta confirming run stays as the post-enable gate. D5 ANSWERED = NO ALLOWLIST — the root failure was sshdo rejecting SILENTLY (exit 1, no output), violating fail-fast-actionable: 'the job should have failed violently with clear error messages; whitelisting something that would hide a configuration error seems counterproductive.' Action: make sshdo rejections loud+actionable (task to file); residual runner-IP timeouts stay tracked in STATBUS-069; CrowdSec untouched. D6 ANSWERED = GO — with the framing 'the question is do we have the best design and how will it play out; we might need to try it out to find out' → build the durable-recreate design, prove by running it. D1 BOUNCED for first-principles justification (why does the read-only window exist at all) — foreman answering; fix build stays held. D2 = general direction approved, detail-level walkthrough required before ratification — cluster-by-cluster interview follows. D3 BOUNCED for precision on temporary-vs-permanent + the actual backoff strategy — foreman restating the full class model (the design distinguishes them; the summary flattened it).
---

author: foreman
created: 2026-07-03 10:44
---
INTERVIEW COMPLETE — ALL SIX RULED (King, 2026-07-03). D1 APPROVED (his clarification: he ratified and understands the window; the bounce was my wording — the ask was only the PostgREST-boot exemption; approved) → engineer building the ALTER ROLE migration now, preempting 092; arc re-run follows. D2 AGREED — executing the SAFE variant of the consolidation: re-labels (11) + verify-closes (Cluster 6: 084/112/113) + the 083→021 merge happen NOW; the ~19 subsumed-closes happen AS THEIR RESOLVER CORES LAND (not on inference) — if the King intended immediate mass-close he can say so, this is the reversible reading. D3 RATIFIED — all four 046 asks (allowance values tunable at build; crash budget=3 counting PROCESS DEATHS only + same-step-twice→park; park columns recovery_attempts/recovery_parked_at; budget boundary flag-write→completed-write) — the precise temporary/permanent/crash class model restated to his satisfaction. 046 becomes buildable AFTER the arc lane validates the 110-fix + 109 (recovery-core order preserved). D4 flip-early / D5 no-allowlist+STATBUS-128 / D6 GO — already dispatched. This queue task closes when D2's safe-variant execution is done; new King decisions get a fresh entry.
---

author: foreman
created: 2026-07-03 19:04
---
CLOSED — all six decisions ruled and executed/dispatched (see comments 1-2 for the verbatim rulings). Residual executions ride their owning tickets: the ~19 consolidation subsumed-closes happen as resolver cores land (071/043 etc.); the seed re-flip waits on doc-025's two oracles; 046 build waits on the arc lane. New King decisions get a fresh queue entry — this pattern (one durable entry, context per item, answers recorded verbatim) worked and is worth repeating.
---
<!-- COMMENTS:END -->
