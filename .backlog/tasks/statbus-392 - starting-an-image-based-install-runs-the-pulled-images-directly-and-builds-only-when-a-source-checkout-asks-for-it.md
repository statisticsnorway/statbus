---
id: STATBUS-392
title: Image-based starts run pulled images directly while source checkouts retain development builds
status: In Progress
assignee: []
created_date: '2026-09-24 16:42'
updated_date: '2026-09-24 18:40'
labels:
  - install
dependencies: []
priority: medium
type: bug
ordinal: 1
---

## Goal

## Implementation note, 2026-09-24

The generated release `VERSION=v...` now selects `--no-build` even with development proxy mode, while untagged source development retains `--build`. Install image pull no longer falls back to a local build for a release, and installer startup explicitly uses `--no-build`. Guarded unit tests exercise both decisions. The measured disposable-VM timing scenario and observation of the actual Finland path remain pending, so #3-4 are open and the ticket is not Done.

`./sb start` distinguishes an image-based installation from a source checkout. Image-based development starts use pulled images without a build, while source development checkouts retain their build-before-start behavior.

## Evidence, 2026-09-24

Current `./sb start` selects build solely from development mode (`cli/cmd/service.go:41-57` at master `7a9cf707e`), and compose mode detection reads `CADDY_DEPLOYMENT_MODE` (`cli/internal/compose/compose.go:445-452` at master `7a9cf707e`). Whether a released image installation exercised this path in Finland is unknown.

## Acceptance Criteria

- [ ] #1 `new: cli/cmd/service_test.go::TestStartImageBasedDevelopmentSkipsBuild` observes no build invocation for an image-based development install.
- [ ] #2 `new: cli/cmd/service_test.go::TestStartSourceDevelopmentBuilds` observes the existing build invocation for a source checkout.
- [ ] #3 `new: test/install-recovery/scenarios/4-image-start-no-build.sh` measures an image start against a baseline pull-plus-start run and requires it to stay within 20 percent of that baseline with zero local builds.
- [ ] #4 `new: test/install-recovery/scenarios/4-image-start-no-build.sh` records whether the image-install path was exercised, rather than claiming an unobserved Finland result.
