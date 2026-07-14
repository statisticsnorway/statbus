---
id: STATBUS-178
title: >-
  import-batch-poisoning: one duplicate-primary controller row fails the whole
  legal_relationship import batch
status: To Do
assignee: []
created_date: '2026-07-13 15:09'
updated_date: '2026-07-14 09:59'
labels:
  - import
  - defect
  - two-tier-validation
  - not-install-upgrade
dependencies: []
references:
  - test/sql/124_duplicate_primary_controller_import.sql
  - STATBUS-120
  - tmp/test-124.log
priority: high
ordinal: 179000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
> NORTH STAR: one unprincipled row errors ONE row (tier-1 fail-fast, actionable message); the rest of the batch imports. A single dirty BRREG roller row must never abort an NSO's entire import.
> FOUND: 2026-07-13 night, by the STATBUS-120 test-first investigation (engineer). The reproducer is test 124 (frozen, uncommitted).
> COMPLEXITY: architect ratifies the fix design (in flight), King one-taps, engineer builds. The fix is a migration modifying import.analyse_legal_relationship.

OBSERVED (real run, test/results/124_duplicate_primary_controller_import.out):
- Direct INSERT path is correct: the DEFERRABLE GiST exclusion `legal_relationship_influenced_primary_excl` (influenced_id=, type_id=, valid_range && WHERE primary_influencer_only) rejects a second overlapping primary.
- IMPORT path is broken: a batch with two primary controllers of the same type on one influenced unit → job state='failed', imported_rows=0, EVERY row (including unrelated valid edges) marked error with key `unhandled_error_process_legal_relationship`. In the mixed test (2 clean edges + 1 conflicting pair) all four rows are rejected.

ROOT CAUSE (both procs read): import.analyse_legal_relationship has no duplicate-primary check (validates idents/rel_type/percentage only), so the conflict reaches import.process_legal_relationship where sql_saga.temporal_merge inserts both rows and the deferred exclusion fires at statement end; temporal_merge cannot attribute it per-row, the EXCEPTION WHEN OTHERS handler fails the whole job.

PROPOSED FIX (engineer, pending architect ratification + King nod): tier-1 duplicate-primary detector in analyse — among primary rows, group by (influenced_id, type_id) with overlapping valid_range and distinct influencing_id; flag (a) intra-batch conflicts and (b) conflicts against EXISTING primaries in legal_relationship; mark conflicting rows state='error', action='skip', key 'duplicate_primary_controller'; valid rows proceed. Test 124 then lands green asserting the correct behavior.

GATE: fix design must be ratified by the architect and one-tapped by the King BEFORE build (fix-design review rule). Test 124 stays frozen with NO expected file until then — blessing imported_rows=0 would enshrine the bug.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Architect ratifies the analyse-layer detector design (intra-batch + vs-existing, temporal-overlap semantics) — recorded on this ticket
- [x] #2 King approves the ratified design before any build
- [ ] #3 Migration adds the tier-1 duplicate_primary_controller detector to import.analyse_legal_relationship; valid rows in a poisoned batch import, conflict rows error per-row with actionable message
- [ ] #4 Test 124 lands green asserting the corrected behavior (direct-INSERT constraint + per-row tier-1 errors + mixed-batch isolation)
- [ ] #5 STATBUS-120 ACs close via the same unit
<!-- AC:END -->

## Comments

<!-- COMMENTS:BEGIN -->
author: architect
created: 2026-07-13 15:14
---
RATIFIED WITH FIVE EXPLICIT RULINGS (architect, 2026-07-13; grounded in the constraint definition doc/db public_legal_relationship.md:36 + the frozen reproducer + both procs per the ticket's trace). The analyse-layer detector is the right design — the two-tier doctrine verbatim: an unprincipled ROW fails fast with an actionable per-row message; the batch lives. The five design points:

(1) OVERLAP SEMANTICS — BYTE-MIRROR THE CONSTRAINT: the detector's predicate is exactly (influenced_id =, type_id =, valid_range &&) among primary-only rows. PostgreSQL range && on half-open ranges means ADJACENT periods ([a,b) then [b,c)) do NOT conflict — disjoint and adjacent are allowed, same as the exclusion. ONE non-obvious detail the build must get right: primary_influencer_only is DENORMALIZED onto legal_relationship rows by a trigger — at analyse time the batch row does not carry it, so the detector derives it from the RESOLVED legal_rel_type.primary_influencer_only, never from a row column.

(2) WHICH ROW ERRORS — ASYMMETRIC BY PROVENANCE: intra-batch conflicts → BOTH rows error. A CSV carries no principled ordering; first-wins invents authority and silently prefers arbitrary data — ambiguity is unprincipled, the operator resolves which is true. vs-EXISTING conflicts → only the INCOMING row errors; the existing row passed the gate before and is settled truth. Same-influencing_id repeats stay OUT of this detector's scope (a different class, temporal-merge's own idempotency territory) — the distinct-influencing_id filter in the proposal is correct.

(3) SOFT-DELETED/SUPERSEDED — the detector's only honest question is 'would process's write violate the exclusion', so it considers EXACTLY the rows the constraint indexes: WHERE primary_influencer_only IS TRUE, nothing more (the constraint has no status predicate). Temporally ended rows exclude themselves via range algebra (closed ranges don't overlap). NO extra status filtering — any divergence from the constraint's predicate is a future false-pass or false-error.

(4) PERFORMANCE SHAPE: intra-batch = an equality-keyed self-join on (influenced_id, type_id) + range && + distinct influencing_id — quadratic only WITHIN each tiny group, linear across the batch; vs-existing = an EXISTS probe per primary batch row that hits the exclusion's own GiST index (same three columns). Explicitly NOT pairwise-across-batch. Per the house rule, EXPLAIN-verify both queries on a large synthetic batch before ship.

(5) ANALYSE IS THE RIGHT LAYER, with two riders: (a) the DEFERRED CONSTRAINT REMAINS THE TRUTH — the detector is UX, not the guard; a concurrent writer between analyse and process still lands on the exclusion, by design; nobody ever weakens the constraint because 'analyse catches it'. (b) BACKSTOP HONESTY: process's EXCEPTION handler stays, but if the exclusion ever fires post-detector that is a DETECTOR GAP — the handler should surface the constraint NAME in the job error (not the generic unhandled_error_*) so the gap is recognizable on sight. That's a two-line improvement riding the same migration.

GATE HONORED: test 124 stays frozen with no expected file until the King's one-tap + the build — blessing imported_rows=0 would enshrine the bug. Ready for the King's morning approval (AC#2).
---

author: foreman
created: 2026-07-14 09:46
---
ON HOLD before AC#2 (2026-07-14): the King flagged that STATBUS-120 mixes two issues — konsern primary seeding vs delt-ansvar (equal-share, non-controlling) loading, which today's load may not support. The batch-poisoning DEFECT stands regardless (one bad row must never kill a batch), but the ratified detector's BOTH-ROWS-ERROR semantics assumes a duplicate-primary pair is always unprincipled — if real shared-control data merely got mapped to a primary type, rejection may be the wrong remedy vs supporting the non-primary shape properly. The 120 discussion (King + architect) rules first; the one-tap waits for it.
---

author: foreman (relaying King)
created: 2026-07-14 09:59
---
KING APPROVED (2026-07-14, AC#2 checked): 'Of course, duplicate primaries are illogical.' The per-row detector builds as ratified (comment #1's five rulings). HOLD LIFTED. Scope boundary from the same ruling: multiple non-controlling interests — even two 50% holders — are LEGAL and must be expressible and reportable; that is NOT this ticket. The bigger question (one power group with marked edges vs a primary power group plus a non-primary power group that can span several primary ones, selectable viewpoint at reporting) is new design work — filed as STATBUS-179. This ticket stays exactly: per-row tier-1 errors for duplicate PRIMARIES, batch lives, test 124 lands green with the fix.
---
<!-- COMMENTS:END -->
