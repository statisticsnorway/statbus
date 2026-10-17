---
id: STATBUS-518
title: >-
  Arc fixture images are ready within a minute of the decision to test a
  candidate
status: To Do
assignee: []
created_date: '2026-10-17 15:40'
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
- [ ] #2 When `app/` is unchanged from the parent commit, reuse the parent app image under the new tag, shown by an app build under 30 s for a migration-only fixture
- [ ] #3 A gate run shows fixture images present before the first arc is ready to start; run ID recorded in Implementation Notes
<!-- AC:END -->
