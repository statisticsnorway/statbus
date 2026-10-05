---
id: STATBUS-449
title: >-
  arc harness dispatched on a ref without published images waits its full 40 min
  budget for base images nobody builds
status: To Do
assignee: []
created_date: '2026-10-05 18:16'
labels:
  - ci
  - testing
  - upgrade
dependencies: []
references:
  - STATBUS-433
priority: low
---

## Issue

`upgrade-arc-harness.yaml` can be started by hand (`workflow_dispatch`) on any ref, but it only works when the base commit's images already exist. Its "Wait for per-commit images (A + B + C)" job polls ghcr for the base images and for each fixture branch's images.

- `construct` explicitly dispatches `images.yaml` for each throwaway `test/*` fixture branch, because a `GITHUB_TOKEN` push does not trigger it.
- Nothing builds the base images (`base_short`). The workflow assumes "A's images are built by the master push, normally ready". `images.yaml` triggers only on pushes to `master` (deliberately not on tags, which point at already-built master commits) and on `workflow_dispatch`.

So a dispatch on a feature branch (any ref whose head was never pushed to master) cannot succeed. It waits out the whole `IMAGES_WAIT_BUDGET_S=2400` and then fails with "Arc images not published".

**Observed:** run 37344014496 (2026-10-05 16:51 to 17:35 UTC, `--ref test/unpark-arc-btrfs-free`, head 210288d2).
- All 11 fixture branches' images were published within 492 s.
- `statbus-{app,worker,db,proxy,sb}:210288d2` (the base) never appeared.
- The job failed at 2400 s, and the run took 44 minutes to report something knowable at second 0.

Consequence: arc-touching test fixes cannot be proven before they reach master. In practice they wait for the next RC's own arc run, which is what happened with the un-park arc's btrfs fix in v2026.10.0-rc.15.

## Fix options (decide when picked up)

1. **Build base images when missing (preferred):** in `construct`, check ghcr for `statbus-*:<base_short>`. If any are missing, `gh workflow run images.yaml --ref <dispatched ref>` as well, so a branch dispatch becomes a real pre-merge arc proof. Cost: one extra cold image build (about 5 to 8 minutes, as observed for the fixtures).
2. **Fail fast:** if base images are missing and the ref is not reachable from master, error at once with a message that names the cause. This is cheaper, but keeps arcs unprovable before merge.

## Related speed lever (same area)

Every arc run builds about 11 fixture branches' images from cold (about 5 to 8 minutes of wall-clock, in parallel). Fixtures differ from the base only by small, deterministic edits. Caching or reusing fixture images keyed by (base_short, fixture recipe hash) would cut that from every RC's arc run. Measure first: the per-RC arc wall-clock split between image wait and scenario execution.

## Acceptance criteria
<!-- AC:BEGIN -->
- [ ] #1 A `workflow_dispatch` of the arc harness on a feature-branch ref either runs the arcs (base images built on demand) or fails within the construct phase with an explicit cause. It never waits out the 40 min image budget for images nobody is building.
- [ ] #2 The RC path (orchestrator dispatch at a tag whose commit was pushed to master) is unchanged in behaviour and duration.
- [ ] #3 Proven by one real feature-branch dispatch and one RC arc run.
<!-- AC:END -->
