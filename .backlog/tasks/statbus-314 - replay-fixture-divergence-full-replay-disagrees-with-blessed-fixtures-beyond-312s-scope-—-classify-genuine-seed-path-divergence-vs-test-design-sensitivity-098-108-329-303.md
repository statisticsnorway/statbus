---
id: STATBUS-314
title: >-
  replay-fixture-divergence: full-replay disagrees with blessed fixtures beyond
  312's scope — classify genuine seed-path divergence vs test-design sensitivity
  (098/108/329/303)
status: To Do
assignee:
  - architect
created_date: '2026-08-28 23:39'
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
