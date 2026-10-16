---
id: STATBUS-392
title: >-
  A release installation starts and restarts from published images; only a
  source checkout builds
status: In Progress
assignee: []
created_date: '2026-09-24 16:42'
updated_date: '2026-10-16 14:12'
labels:
  - release-bug
  - install
dependencies: []
priority: medium
type: bug
ordinal: 1
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
### North Star
Starting or restarting StatBus on a release installation uses the published images and never builds from source; only a source development checkout builds.

### Zoom out
Two kinds of box can both run the web entry point in development mode: a developer's source checkout, where building from source is the point, and a released installation that a country runs in development mode (for example a laptop test). The compose files carry build blocks, so if "development mode" alone decides, a released installation can start a slow, surprising local build during an ordinary start or a recovery. The right question is "is this a source checkout?", answered from the generated `VERSION`: a release tag means published images, anything else means source.

### Zoom in
- **Finding, Finland triage 2026-09-24 (v2026.09.2):** `./sb start` added `--build` whenever the mode was development, even on an image-based install (`cli/internal/service/service.go:55` then). Install itself avoided it only because its Services step used a plain `up -d`. Whether Finland's box actually hit this path is unknown.
- **Shipped (v2026.09.3):** `05a4fe9dd`. `startBuildsFromSource` (`cli/cmd/service.go`) returns false unless development mode AND `VERSION` is not a release tag (no `v` prefix, or a `-g` describe suffix). `./sb start` then passes `--no-build`; install startup also uses `--no-build`, and a release image pull no longer falls back to a local build.
- **Proof, unit:** `TestStartImageBasedDevelopmentSkipsBuild`, `TestStartSourceDevelopmentBuilds` (`cli/cmd/service_start_test.go`), green 2026-10-15.
- **Gap found 2026-10-15:** `./sb restart` (`cli/cmd/service_restart.go`) still adds `--build` whenever `compose.IsDevelopmentModeInDir` is true; it was not switched to `startBuildsFromSource`. So restarting a released development-mode installation can still build locally.

### Closing review
- **Memory:** none needed.
- **Documentation:** `./sb start --help` states the rule; `./sb restart --help` needs the same line once it follows it.
- **Cleanup:** none.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 `./sb start` on a release installation in development mode passes `--no-build` (`TestStartImageBasedDevelopmentSkipsBuild`)
- [x] #2 `./sb start` in a source development checkout still builds (`TestStartSourceDevelopmentBuilds`)
- [x] #3 `./sb restart` builds from source only in a source checkout and passes `--no-build` on a release installation, by the same rule as `./sb start` (`startBuildsFromSource`)
- [ ] #4 [Owner] Decide whether the real-box timing scenario (`4-image-start-no-build.sh`, image start within 20% of a pull-plus-start baseline) is required, and record it in Implementation Notes. No: check this and set Done after AC3. Yes: add that scenario as a new criterion.
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
### Evidence
- **AC1-2:** green in Go Test (v2026.09.3); re-run green locally on master, 2026-10-15.
- **AC3:** open; `cli/cmd/service_restart.go` checks `compose.IsDevelopmentModeInDir(dir)` alone before appending `--build` (master `cb34436b4`).
- **Superseded criteria:** the restyle named `cli/cmd/service_test.go`; the tests landed in `service_start_test.go`. The stale "To Do" status header and 09-24 implementation note were folded into Zoom in.

### AC3 (e4af9ef19)
- `restartUpArgs` (`cli/cmd/service_restart.go`) decides --build/--no-build with `startBuildsFromSource`, the same rule as start. `./sb restart --help` states the rule.
- **Red, then green:** `TestRestartUpArgsFollowStartBuildRule_STATBUS392` ran against the old rule: VERSION=v2026.10.2 got `--build` for both profile all and profile app, so it failed. With the fix it passes, and the source cases (VERSION=local, `-g` describe) still build. The whole `cli/cmd` package passes locally.
- No other build decision depends on development mode alone; `rg IsDevelopmentMode` shows only startBuildsFromSource.
- Waiting: Go Test in CI for e4af9ef19.

- **Correction:** the commit is e622a4f9a, not e4af9ef19 as written above. That first commit attempt failed because the new test file was untracked.

- **CI:** Go Test passed on 8510ee36a, which contains e622a4f9a. AC3 is done. Only the [Owner] AC4 decision remains.
<!-- SECTION:NOTES:END -->
