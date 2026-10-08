---
id: STATBUS-476
title: >-
  public.reset activity_category replacement join is unscoped by standard
  (ambiguous for 418 rows; masked by the parent trigger)
status: To Do
assignee: []
created_date: '2026-10-08 16:34'
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
- [ ] #1 public.reset's replacement join conditions on replacement.standard_id = to_delete.standard_id
- [ ] #2 pg_regress test manufactures the same path in two standards with a custom override and asserts the reset reparents within the override's standard, with the parent trigger's correction not relied upon (e.g. assert what the join selects)
- [ ] #3 Test 305's changed_children_count and 0 cross-standard links unchanged
<!-- AC:END -->
