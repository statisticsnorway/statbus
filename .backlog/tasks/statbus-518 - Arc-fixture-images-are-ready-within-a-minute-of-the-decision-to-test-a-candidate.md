---
id: STATBUS-518
title: >-
  Arc fixture images are ready within a minute of the decision to test a
  candidate
status: To Do
assignee: []
created_date: '2026-10-17 15:40'
updated_date: '2026-10-20 19:46'
labels:
  - ci
  - lxd
dependencies: []
priority: medium
ordinal: 444204
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
### North Star
The synthetic upgrade targets the arcs need are ready before the arcs could start, so they never hold up the gate.

### Zoom out
Arcs upgrade the candidate to synthetic commits (candidate plus a test migration). Those commits need real images. They depend only on the candidate commit, so they can be built as soon as the candidate is chosen, and an image whose source did not change can be reused rather than rebuilt.

### Zoom in
- v2026.10.2-rc.01: 11 fixture commits; builds dispatched 22:52:14-22:52:29 after smoke and dev, finished 22:54:34-22:55:00; the arc job saw them at 22:58:11 (30 s poll, wait job started after construct).
- Build cache works: db, proxy, worker 21-27 s. The app image takes 1.5-2 min: `app/Dockerfile` passes `ARG COMMIT` into `next build`, so each new commit rebuilds the app although a migration-only fixture leaves `app/` unchanged. `images.yaml` already retags a parent's images for exempt-only pushes.
- Owner direction 2026-10-17 (T6 in `tmp/lxd-gate-design.md`): builds must hit the cache; 30 s polling is acceptable.

### Closing review
- **Memory:** none needed.
- **Documentation:** the arc harness header states when fixtures are built.
- **Cleanup:** none.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Dispatch the fixture construct and image builds at the gate decision, in parallel with smoke, shown by build start times before smoke ends in a run
- [ ] #2 A gate run shows fixture images present before the first arc is ready to start; run ID recorded in Implementation Notes
- [ ] #3 In `app/Dockerfile`, stamp the commit after `next build` instead of before it, so an unchanged `app/` reuses the cached build and each image still reports its own commit; shown by an app build under 30 s for a migration-only fixture
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
2026-10-20 owner decisions:
- Build first, stamp after: ARG COMMIT moves after next build in app/Dockerfile, so the expensive build is cached whenever app/ is unchanged and only the small stamp step reruns. Each image still reports its own true commit (/_statbus-build.json; release identity; c-rollback-resurrection-arc checks it). Replaces the earlier 'retag the parent app image' idea, which would report the parent's commit.
- This speeds up the app image for every commit that leaves app/ unchanged (migration-only, cli, harness, backlog), not just fixtures. Commits that change app/ still rebuild, as they must.
- Start fixture construct + image builds at the gate decision, in parallel with smoke. Arcs still wait for the images before using them; the run in criterion 3 confirms they are ready in time.
- Order: stamp-after-build first (testable on any push), then the early start, then the real-run check at the next RC.
<!-- SECTION:NOTES:END -->
