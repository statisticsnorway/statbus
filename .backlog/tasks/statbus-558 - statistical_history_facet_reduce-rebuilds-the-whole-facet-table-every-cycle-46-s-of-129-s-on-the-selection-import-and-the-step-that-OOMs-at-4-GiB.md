---
id: STATBUS-558
title: >-
  statistical_history_facet_reduce rebuilds the whole facet table every cycle:
  46 s of 129 s on the selection import, and the step that OOMs at 4 GiB
status: In Progress
assignee: []
created_date: '2026-11-02T13:15:00Z'
updated_date: '2026-11-02T13:15:00Z'
labels: []
dependencies: []
type: bug
ordinal: 481204
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Survey 2026-11-02 (tmp/survey-findings.md, plan tmp/survey-facet-merge-plan.txt): 4 calls, 45.6 s, max 20.6 s, all in one MERGE. HashAggregate over all 214k statistical_history_facet_partitions rows spills (5 batches, 38 MB disk), Sort 139k, Merge Full Join with a full scan+sort of the 89k target. Since e69785896 (2026-04-30) the reduce is a global MERGE with NOT MATCHED BY SOURCE DELETE: the earlier dirty-slot Path B could not delete stale target rows whose dims were not in pre_dirty_dims, causing over-counts. The dirty slots are now read for logging only. To be understood before coding, with the owner: what the partition hashing and period restriction guarantee, which target rows a cycle can change, and how to restrict the merge to them while keeping self-healing. The unit facet reduce has the same shape.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 The cause is written down and agreed with the owner before code
- [ ] #2 The reduce touches only rows a cycle can change, and stays correct for the stale-row case that e69785896 fixed (regression test)
- [ ] #3 Selection import: facet reduce time and the 4 GiB run are measured before and after
<!-- AC:END -->
