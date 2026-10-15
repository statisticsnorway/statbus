---
id: STATBUS-449
title: >-
  arc harness dispatched on a ref without published images waits its full 40 min
  budget for base images nobody builds
status: Done
assignee: []
created_date: '2026-10-05 18:16'
updated_date: '2026-10-15 19:43'
labels:
  - ci
  - testing
  - upgrade
dependencies: []
references:
  - STATBUS-433
priority: low
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
### North Star
Dispatching the upgrade-arc harness on a branch whose images do not exist fails in seconds with the real cause, instead of waiting 40 minutes for images nobody is building.

### Zoom out
The arc harness only works when the base commit's images exist, and those are built only by pushes to master. A hand dispatch on a feature branch therefore waited out the whole image budget and then reported "Arc images not published", something knowable at second zero. Two options were weighed: build the missing base images on demand, which makes arcs provable before merge at the cost of a cold build, or fail fast with the cause. Owner choice (2026-10-06): fail fast. The release-candidate path, where the base is on master, must not change.

### Zoom in
- **Incident, 2026-10-05:** run `37344014496` on `test/unpark-arc-btrfs-free` (head `210288d2`): all 11 fixture branches' images published within 492 s, but `statbus-{app,worker,db,proxy,sb}:210288d2` never appeared, and the job failed at 2400 s after 44 minutes.
- **Shipped (`775464d38`, reviewed MERGE in `tmp/449-overnight-review.md`, in v2026.10.1):** `construct` resolves the base to its full SHA, refreshes master ancestry, and only when the base is off master checks its five image manifests. An unavailable base fails before any fixture is created, naming each missing manifest and Docker's own error. A base on master keeps the normal publication wait; the wait job and every later job are unchanged.
- **Proof, real feature-branch dispatch:** run `37541454901` (2026-10-06, `test/449-unpublished-base-fixed-20261006`). Construct failed 22 s after starting with `Manifest unavailable: ghcr.io/statisticsnorway/statbus-app:fd72b69d; docker manifest inspect said: manifest unknown` (and the same for worker, db, proxy). The image wait, fixture matrix and guest ramp were all skipped; the whole run took 1 min 19 s.
- **Proof, RC path:** arc runs at `v2026.10.0-rc.20` (`37578475601`, success, 59 min 41 s) and `v2026.10.1-rc.04` (`38740570520`, success) used the normal wait and guests.
- **Not done (separate lever):** reusing fixture images across runs keyed by base and recipe; that would cut every RC's arc time and is not part of this ticket.

### Closing review
- **Memory:** none needed.
- **Documentation:** none needed; the error names its cause.
- **Cleanup:** none.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 A `workflow_dispatch` of the arc harness on a feature-branch ref whose base images are unpublished fails within construct, naming the missing images, and never waits out the image budget (run `37541454901`, failed in 22 s)
- [x] #2 The RC path (orchestrator dispatch at a tag on master) keeps its normal image wait and guest runs (`37578475601` at v2026.10.0-rc.20, `38740570520` at v2026.10.1-rc.04, both success)
- [x] #3 Proven by one real feature-branch dispatch and one real RC arc run (the two runs above)
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
### Evidence
- **AC1:** run `37541454901`, head `fd72b69d7` (contains `775464d38`); construct failed in 22 s naming each missing manifest; wait, matrix and ramp skipped.
- **AC2-3:** arc runs `37578475601` and `38740570520`, success.
- **History:** the 2026-10-06 implementation and review notes are in Git history.
<!-- SECTION:NOTES:END -->
