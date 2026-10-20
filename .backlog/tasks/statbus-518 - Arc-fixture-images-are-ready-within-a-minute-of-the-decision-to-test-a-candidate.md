---
id: STATBUS-518
title: An app image with unchanged app source builds from cache
status: In Progress
assignee: []
created_date: '2026-10-17 15:40'
updated_date: '2026-10-20 20:43'
labels:
  - ci
  - lxd
dependencies: []
priority: medium
type: enhancement
ordinal: 444204
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
### North Star
An app image whose `app/` source is unchanged builds from cache, so arc fixtures (and every other commit that leaves `app/` alone) get their app image in seconds.

### Zoom out
Arcs upgrade the candidate to synthetic commits (candidate plus a test migration). Those commits need real images. They depend only on the candidate commit, so they can be built as soon as the candidate is chosen, and an image whose source did not change can be reused rather than rebuilt.

### Zoom in
- v2026.10.2-rc.01: 11 fixture commits; builds dispatched 22:52:14-22:52:29 after smoke and dev, finished 22:54:34-22:55:00; the arc job saw them at 22:58:11 (30 s poll, wait job started after construct).
- Build cache works: db, proxy, worker 21-27 s. The app image takes 1.5-2 min: `app/Dockerfile` passes `ARG COMMIT` into `next build`, so each new commit rebuilds the app although a migration-only fixture leaves `app/` unchanged.
- Owner direction 2026-10-17 (T6 in `tmp/lxd-gate-design.md`): builds must hit the cache; 30 s polling is acceptable.

### Closing review
- **Memory:** none needed.
- **Documentation:** `app/Dockerfile` states why the stamp follows the build (done in d97541322).
- **Cleanup:** none.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 In `app/Dockerfile`, stamp the commit after `next build`; shown by an app build under 30 s for a migration-only fixture in a real candidate run (run ID recorded in Implementation Notes)
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
2026-10-20 owner decisions:
- Build first, stamp after: ARG COMMIT moves after next build in app/Dockerfile, so the expensive build is cached whenever app/ is unchanged and only the small stamp step reruns. Each image still reports its own true commit (/_statbus-build.json; release identity; c-rollback-resurrection-arc checks it). Replaces the earlier 'retag the parent app image' idea, which would report the parent's commit.
- This speeds up the app image for every commit that leaves app/ unchanged (migration-only, cli, harness, backlog), not just fixtures. Commits that change app/ still rebuild, as they must.
- Starting fixture builds at the gate decision moved to STATBUS-423 (see the note below).
- Order: stamp-after-build first (testable on any push), then the early start, then the real-run check at the next RC.

2026-10-20 owner decision: criterion 'dispatch fixtures at the gate decision' moved to STATBUS-423 (the queue runner removes the smoke-then-arcs concurrency ordering that blocks an early start in today's workflows). Remaining here: the stamp-after-build change (d97541322, local proof: second build 2 s with next build CACHED, each image stamps its own commit) and its measurement on real runs.
<!-- SECTION:NOTES:END -->
