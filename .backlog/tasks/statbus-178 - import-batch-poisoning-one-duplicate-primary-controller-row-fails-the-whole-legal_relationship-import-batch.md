---
id: STATBUS-178
title: >-
  import-batch-poisoning: one duplicate-primary controller row fails the whole
  legal_relationship import batch
status: To Do
assignee: []
created_date: '2026-07-13 15:09'
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
- [ ] #1 Architect ratifies the analyse-layer detector design (intra-batch + vs-existing, temporal-overlap semantics) — recorded on this ticket
- [ ] #2 King approves the ratified design before any build
- [ ] #3 Migration adds the tier-1 duplicate_primary_controller detector to import.analyse_legal_relationship; valid rows in a poisoned batch import, conflict rows error per-row with actionable message
- [ ] #4 Test 124 lands green asserting the corrected behavior (direct-INSERT constraint + per-row tier-1 errors + mixed-batch isolation)
- [ ] #5 STATBUS-120 ACs close via the same unit
<!-- AC:END -->
