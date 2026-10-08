---
id: STATBUS-476
title: >-
  public.reset activity_category replacement join is unscoped by standard
  (ambiguous for 418 rows; masked by the parent trigger)
status: Done
assignee: []
created_date: '2026-10-08 16:34'
updated_date: '2026-10-08 17:48'
labels:
  - sql
dependencies: []
priority: medium
ordinal: 402204
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
NORTH STAR: public.reset decides a deleted custom override's replacement within the override's own standard, so its result never depends on the parent-derivation trigger correcting it.

FOUND during STATBUS-473 review (rabbit). public.reset scope getting-started/all joins activity_category_to_delete to its replacement ON to_delete.path = replacement.path AND NOT replacement.custom, with NO standard condition. The seed has 2 standards and 424 non-custom paths present in both. In test 305's scenario (Norway getting-started, 1811 custom overrides in nace_v2.1), the join has: 225 overrides with exactly one same-standard candidate, 418 AMBIGUOUS (one same-standard plus one other-standard candidate, so the UPDATE ... FROM picks one arbitrarily), 256 with ONLY an other-standard candidate, 912 with none.

Measured on master+473 (statbus_473_reset_with, own clone): after the reset, 0 cross-standard parent links, 0 orphans, changed_children_count 726. It is correct today ONLY because public.lookup_parent_and_derive_code (BEFORE INSERT OR UPDATE, scoped to own standard by 473) re-derives parent_id on every UPDATE and overrides whatever the join wrote. Proof: forcing UPDATE SET parent_id = <isic_v4 row> on nace A.01.1.1 stored the nace parent 768. The join's choice is dead code that is wrong for 674 of 1811 rows. Also: 0 children hang under a custom parent with no same-standard twin, so scoping the join orphans nothing.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 public.reset's replacement join conditions on replacement.standard_id = to_delete.standard_id
- [x] #2 pg_regress test manufactures the same path in two standards with a custom override and asserts the reset reparents within the override's standard, with the parent trigger's correction not relied upon (e.g. assert what the join selects)
- [x] #3 Test 305's changed_children_count and 0 cross-standard links unchanged
<!-- AC:END -->

## Definition of Done
<!-- DOD:BEGIN -->
- [ ] #1 Fast Tests with pg_regress actually run, green on a commit containing 08d347c8f; blocked by STATBUS-481
<!-- DOD:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
LANDED as 08d347c8f (migration 20261008174433_statbus_476_reset_reparents_activity_categories_within_their_own_standard, test 139).
Fix: public.reset's activity_category replacement join adds AND to_delete.standard_id = replacement.standard_id. The rest of reset is unchanged (built from the \sf dump; the down migration is the dump).

THE TRIGGER MASKED IT, so the test forces the situation: public.lookup_parent_and_derive_code (BEFORE INSERT OR UPDATE, scoped to the row's own standard since STATBUS-473) re-derives parent_id on every update and overwrites whatever reset's join wrote. Test 139 therefore runs ALTER TABLE activity_category DISABLE TRIGGER lookup_parent_and_derive_code_before_insert_update inside its rolled-back transaction, so it asserts reset's own choice and not the trigger's correction. The ambient data alone could never show the defect.

RED (pre-fix) and GREEN, on my own clones of statbus_seed, trigger disabled, Norway getting-started data (as test 305 loads it):
- Candidates for the 1811 deleted overrides (measured earlier): 225 same-standard only, 418 ambiguous (same and other standard), 256 other-standard only, 912 none.
- Pre-fix (statbus_476_scratch), the same in 3 repeated runs: links after reset are isic_v4->isic_v4 745, nace_v2.1->isic_v4 653, nace_v2.1->nace_v2.1 372. reset itself pointed 653 nace children at isic parents.
- Fixed (statbus_476_fixed): isic_v4->isic_v4 745, nace_v2.1->nace_v2.1 1025, 0 cross-standard. changed_children_count 726, unchanged (AC#3).
- Manufactured case (139.1): A.01.1 exists as a system row in isic_v4 and nace_v2.1, and nace_v2.1 gets a custom override with child A.01.1.1. Pre-fix: the child ends under isic_v4 A.01.1. Fixed: under nace_v2.1 A.01.1 (system).
- pg_regress on master + 476: 139, 133, 305, 306, 108, 015 ok. Test 305 is unchanged (changed_children_count 726, with the trigger enabled as in production). Down/up round trip clean.
doc/db: generated once from statbus_seed = master + 476: 0 added, 0 deleted, 1 modified (public_reset), 582 = 582.
CI: none claimed while STATBUS-481 blocks Images.
<!-- SECTION:NOTES:END -->
