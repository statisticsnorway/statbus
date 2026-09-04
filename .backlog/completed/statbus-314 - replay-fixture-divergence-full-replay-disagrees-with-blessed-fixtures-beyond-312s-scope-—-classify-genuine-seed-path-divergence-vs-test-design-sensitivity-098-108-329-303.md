---
id: STATBUS-314
title: >-
  replay-fixture-divergence: full-replay disagrees with blessed fixtures beyond
  312's scope — classify genuine seed-path divergence vs test-design sensitivity
  (098/108/329/303)
status: Done
assignee:
  - architect
created_date: '2026-08-28 23:39'
updated_date: '2026-08-29 10:59'
labels:
  - testing
  - migrations
  - release
dependencies: []
priority: high
type: bug
ordinal: 307000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
NORTH STAR: the same invariant STATBUS-312 restored for import mappings — a full-from-scratch replay must equal the fleet's state, and a blessed expected file must mean the tree's code passed — holds for EVERYTHING, not just the table 312 repaired. Tonight's genuine full replay (the mechanic's 312 validation run, 5 of 92 red) says it does not yet.

THE EVIDENCE (mechanic's dig, diff-verified, no truncation):
- 108_test_code_gen: still red AFTER the 312 repair — but the remaining diff is entirely in import_data_column_baseline (a table 312 never writes): priorities shifted +6 (expected 8/9/10 → actual 14/15/16; 19/20/21 → 25/26/27, consistent). Generator traced: import_generate_external_ident_data_columns sets priority = v_base_priority + 2 + ident_type.priority, deterministic and idempotent — so the shift is v_base_priority ITSELF differing between replay paths. THE QUESTION THAT DECIDES THE FIX: v_base_priority reads "whatever exists right now" — if that makes it order-dependent across the migration sequence, this is a SECOND instance of 312's exact disease (a released migration's data operation keyed to its position), and fleet databases may carry 8/9/10 where a fresh full replay builds 14/15/16 — a genuine state divergence needing a forward repair, not a re-bless. If instead the blessed baseline was simply built on a nonrepresentative fixture, it is a re-bless. These remedies point in OPPOSITE directions; classification must come before any fix.
- 098_user_delete_door: expects user id 2, full replay yields 32 — and the SAME test ran green with id 2 earlier tonight on a template from tonight's OTHER full rebuild. Two full rebuilds disagreeing on auth.user id allocation means something in the replay advances the sequence nondeterministically (or path-dependently). Whatever the cause, 098 asserting absolute ids is a test-design defect by the house's own rule (deterministic tests: DELETE + ALTER SEQUENCE RESTART) — landed tonight, pre-release, cheap to fix — but the 2-vs-32 mechanism should be NAMED, not papered over, since it may be another divergence signal.
- 329_test_upgrade_schema_skew: expects the seeded id=1 public.upgrade row (or from_commit_version IS NOT NULL), full replay has 0 — the fixture assumes a row a from-scratch replay does not produce.
- 303_* explain plans: did NOT revert after the 312 repair — per the standing disposition on 312, that means a separate cause (statistics/content on full replay), now part of this family.

CONSTRAINT carried over from 312's ruling: the fleet/artifact is authoritative; replay is the reconstruction; repairs move replay toward the fleet, never the reverse. And the durable rule this family keeps violating: a migration's data operations must be expressed so their result does not depend on their position in the sequence.

FOR THE ARCHITECT: classify each of the four (genuine divergence → forward repair per 172; fixture sensitivity → deterministic-test fix or re-bless), rule the fix order, and rule how each red is treated for the rc.17 cut (fixed aboard vs expected-and-attributed with the pre-declaration written BEFORE the chain runs).

WHAT IS ACHIEVED: the invariant is restored across the whole suite, not per-table as defects surface; and no red from this family can masquerade as a current unit's failure again.
<!-- SECTION:DESCRIPTION:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
**Architect ruling (2026-08-29), all four classified — two defect families and one non-defect:** (1) 108 = CONFIRMED second instance of 312's disease, verified at the line (import_generate_external_ident_data_columns line 27: `SELECT COALESCE(MAX(idc.priority), 0) INTO v_base_priority` — MAX over whatever exists at run time). FORWARD REPAIR per 172; re-bless rejected — it would record the replay's state as truth and permanently diverge from the fleet. Assigned: mechanic, after the 252 shadow persistence, derivation-check-first with stop-and-escalate. (2+3) 098 and 329 = the same test-design defect (a test inheriting state it did not create): 098 asserts absolute user ids (house-rule violation), 329 assumes a seeded upgrade row a fresh replay legitimately lacks — the replay is right, the fixtures are wrong. Both fixed ABOARD rc.17, assigned: engineer. The 2-vs-32 nondeterminism signal 098's fix erases is preserved as STATBUS-315 (tester) per the ruling's explicit requirement. (4) 303 = not a defect: explain plans are the baseline surface with a ratified convention (review, discard trivial drift) — foreman reviewed the diffs (join-order reshuffles among small lookup tables, no new large-table seq scans, no timing regressions) and discarded. rc.17 disposition: 098/329 aboard; 108 aboard if the repair lands, else EXPECTED-AND-ATTRIBUTED with the pre-declaration written BEFORE the chain runs; 303 not a red. The earned rule is now in AGENTS.md beside the 172 discipline: a migration's data operations must not derive values from aggregate reads of current state.

**098 + 329 LANDED at d70d93d94** (engineer, both green, all 119 diff lines read before blessing). 098: four raw-id projections → same-replay email-lookup comparisons, strictly stronger than the absolute ids they replace. 329: the briefed premise was corrected against the seed — public.upgrade is EMPTY in the seed; the old predicate matched the test's OWN Part A insert, which got id 1 only by sequence accident. Now addressed by the test's self-chosen sha, with from_commit_version kept in the predicate deliberately (exercising the 42703 column is the test's purpose). REMAINING on 314: the 108 forward repair (mechanic, after shadow persistence, derivation-check-first) — aboard rc.17 if it lands, else pre-declared. 303: reviewed and discarded per convention. Rule landed in AGENTS.md at 08df247c6.

**PRE-DECLARATION for the rc.17 chain, written BEFORE the run (mechanic 2026-08-28 23:52 UTC, board-recorded 2026-08-29 morning):** 108_test_code_gen is EXPECTED RED on any full-replay validation in this candidate's chain. Cause: import.generate_link_lu_data_columns() is non-idempotent — empirically proven (+2 per call with 2 active ident types, +6 total matching the diff exactly): its base read is MAX(priority) over ALL the step's columns with no purpose filter, so every lifecycle-callback firing re-bases off its own prior output and climbs. Each box drifts independently; there is NO fleet-wide canonical 8/9/10 — the blessed values were one snapshot of one box's drift, so the 314 ruling's repair direction is amended: converge every box TO THE FORMULA (static base + priority-derived offset, the two sibling generators' proven pattern), not to a historical value. Fleet impact: none until repair — each box's drifted values are internally stable. The repair (procedure fix at source + one converging CALL + invariant test) is being built now and rides the NEXT candidate; architect reviewing the formula shape in parallel.

**Architect amendment to his own 314 rule (2026-08-29, adopted):** 'the fleet is authoritative' has an unstated precondition — a COHERENT fleet state. The non-idempotent generator gave each box private drift: there is no fleet state, only scatter, so 8/9/10 was one box's snapshot. Amended rule: THE FLEET IS AUTHORITATIVE WHEN THE FLEET IS COHERENT; WHERE A DEFECT MADE IT INCOHERENT, THE DEFINITION IS AUTHORITATIVE AND EVERY BOX CONVERGES TO IT. Build amendments for the 108 repair: stat_vars shape (idempotent by construction — pure function of the driving row's static priority; no MAX over anything the generator writes, filtered or otherwise); the invariant is specified rather than the arithmetic (output identical regardless of run count and current table contents); THREE test cases — twice-in-a-row identical, already-correct untouched, DRIFTED-CONVERGES (the one proving the single CALL repairs real boxes, which also discharges the 312-interplay question); down migration dumps-first, restores the old non-idempotent procedure deliberately (with a comment), and must NOT revert converged priorities (correct data stays, per the 309-deleted_at principle). Updating 108's expected alongside the source fix is a fixture following a corrected generator, not a re-bless.
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
All four items resolved, and the whole family rides rc.17 — the pre-declaration RETIRES unused. (1) 108: the drift died at source in 4488ef6ba — import.generate_link_lu_data_columns rebuilt on the stat_vars pure-function shape (targeted lookup of the never-written primary_for_legal_unit row + the ident type's own static priority; no MAX anywhere), one CALL converging every database from wherever it drifted; test 126 pins the three ruled cases (idempotent, untouched, drifted-converges); 108 genuinely passes with its own determinism sections finally empty. (2+3) 098/329 landed at d70d93d94 as deterministic-fixture fixes. (4) 303/109 drift reviewed and discarded per convention, twice. Durable outcomes beyond the fixes: the AGENTS.md rule (no aggregate-derived data operations in migrations, 08df247c6), the amended authority rule on the record (fleet authoritative when coherent; the definition where a defect scattered it), STATBUS-315 preserving the id-nondeterminism signal, STATBUS-316 filing the general sequence normalization. Found because one full replay was actually read instead of re-blessed.
<!-- SECTION:FINAL_SUMMARY:END -->
