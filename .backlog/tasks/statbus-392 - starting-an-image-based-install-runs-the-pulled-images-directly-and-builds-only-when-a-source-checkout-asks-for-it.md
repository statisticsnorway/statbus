---
id: STATBUS-392
title: >-
  sb behaves by how it was built: a release build pulls and runs published
  images and keeps developer commands out of the way; a source build builds
status: Done
assignee: []
created_date: 2026-09-24 16:42
updated_date: '2026-10-28T01:09:00Z'
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
What runs on a release installation is exactly what we published. A developer's source build builds what it changed. The sb binary knows which one it is, and every command follows that one answer.

### Zoom out
The binary carries its build identity: a tagged release (`v2026.10.3-rc.01`) or a source build between tags (`v2026.10.3-23-g34cd535ea`). That is the source of truth (owner, 2026-10-20). Not CADDY_DEPLOYMENT_MODE, which describes how the site is served. A country testing a release on a laptop in development mode is still a release install, and a developer can exercise release behaviour locally by running a release binary.

Compose with both image: and build: (all our services) uses the image if present, pulls if absent, and builds if the pull fails. Install and upgrade already pull first, verify, and then start with --no-build, so a running stack means the images were pulled. Start and restart follow the same rule.

### Zoom in
- **History:** the Finland triage (2026-09-24) found `./sb start` forcing --build in development mode. 05a4fe9dd and e622a4f9a answered that with a separate guess (startBuildsFromSource, from VERSION in .env) and a forced --no-build. The owner pushed back (2026-10-20): that tested flags rather than outcomes, and the timing test (old AC4) would have tested Docker Compose, not us.
- **Images missing on a release box** only happens after a deliberate prune or disk clean-up. A cheap local check (no network) covers it: pull only when missing, and say why.
- **Command groups:** sb has no grouping or mode-dependent visibility today (checked: no cobra AddGroup/GroupID anywhere). Cobra hides per command; groups are headings. Visibility is decided before help is drawn.

### Closing review
- **Memory:** none. **Documentation:** the help text of start, restart and build, and the hint line in the root help. **Cleanup:** remove startBuildsFromSource and its tests.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 One function answers 'release build or source build' from the binary's build identity, and start, restart and command visibility all use it; startBuildsFromSource is removed
- [x] #2 A source build: ./sb start and ./sb restart run compose up with --build
- [x] #3 A release build: start and restart check locally that this version's images exist; if any is missing they print why, pull, and then start with --no-build; a failed pull stops with the remedy (check the network, or build with ./sb build)
- [x] #4 ./sb --help groups commands as Operations and Development. On a release build the Development group is hidden, the help ends with a line naming ./sb help --all, ./sb help --all lists every command, and a hidden command still runs and shows its own --help
- [x] #5 The clean LXD install and upgrade scenarios assert that every StatBus service image on the box carries a ghcr.io registry digest (pulled, not built), read from Docker's image records
- [x] #6 Go tests and the fast suite pass, and CI passes; old AC4 (real-box timing scenario) is withdrawn by the owner
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

### Owner pushback 2026-10-20: the design is over-engineered
- **Owner:** a real-box timing test would test Docker Compose, not our code. More importantly, forcing `--no-build` defeats Compose's own behaviour: use the cached image if present, pull it if not, build if the pull fails. That always works. With --no-build, the image must exist or be pullable, or start fails.
- **Checked locally (tmp/392-compose, a service with both image: and build:, like all of ours):**
  - Image present: plain `up -d` uses it, no build. `--build` rebuilds it.
  - Image absent: plain `up -d` pulls, and if that fails, builds. `--no-build` pulls, and if that fails, errors with 'No such image'.
- **Conclusion:** the original defect (Finland triage) was `--build` forced in development mode. Dropping `--build` was the fix. Adding `--no-build` plus the source-checkout/release decision (startBuildsFromSource, a check on the VERSION string) replaced a self-healing default with 'pull or fail'.
- **Proposed redesign:** `./sb start` and `./sb restart` run plain `up -d` with no build flag. Remove startBuildsFromSource. Tests assert that neither flag is passed. Developers build explicitly (./dev.sh, docker compose build). AC4 (the real-box timing scenario) is withdrawn: No.
- **Open (owner):** in a source checkout, `./sb start` would no longer rebuild after a code change. That is acceptable if development builds belong to ./dev.sh.

### Agreed design (owner, 2026-10-20)
- **1b:** the build identity decides. **2:** release start/restart do a cheap image check, pull only if missing (saying why), then --no-build; a source build uses --build. **3:** Operations and Development groups; Development hidden on release builds; `./sb help --all` shows it, with a hint line in the regular help; a command's own --help always works (cobra).
- **Test:** the outcome (registry digests on the clean install and upgrade), not flag strings.
- Earlier AC1-3 (the --no-build design) are superseded by this design; their commits stay in history.

- **Design written up:** doc/sb-build-identity.md.

### Build-identity redesign implemented (e65fe668a, 2026-10-20)
- **AC1:** `isReleaseBuild`/`isReleaseBuildVersion` (cli/cmd/build_identity.go) decides from the version ldflag: a tag (v2026.10.3, v2026.10.3-rc.01) is a release build; a -<n>-g<sha> describe, dev, or empty is a source build. start (service.go), restart (service_restart.go), install's pull fallback (install.go runPullImages, one-line change approved by rabbit after dolphin finished 514) and help visibility (applyBuildVisibility) all use it. startBuildsFromSource and its flag-string tests removed; restartUpArgs moved to service_up_args.go behind the dockerImageOps seam.
- **AC2:** TestUpArgsSourceBuild_STATBUS392: start = --profile all -d --build, restart adds --wait; source build never touches the image check.
- **AC3:** TestUpArgsReleaseImagesPresent/ImagesMissingPulls/PullFailureNamesRemedy_STATBUS392: exact argv equality, all-present is silent with no pull, missing prints the prune line and pulls once then --no-build, failed pull error names the network and ./sb build.
- **AC4:** help_groups_test.go: release root help is exactly the Operations set and ends with the hint line; source root help is Operations+Development and ends with cobra's footer; help --all lists every command; a hidden build command still resolves, is runnable, and renders its own help. Also smoke-tested with real binaries: /tmp/sb-release --help (hint line, no dev commands), help --all (all 8 dev commands incl. release), build --help works; /tmp/sb-dev --help shows both groups. Cobra detail: group headings draw even when empty, so build_identity.go ships a help template that skips empty groups; both groups must stay registered (cobra panics on an unregistered GroupID).
- **Red/green:** tmp/392-red.log (build failure against the old API) and tmp/392-green.log (go test ./cmd ok, 52.5s). gofmt clean, golangci-lint 0 issues.
- **AC5 (wired, harness-tested):** assert_service_images_pulled_from_registry in test/install-recovery/lib/assertions.sh asserts a ghcr.io @sha256 RepoDigests entry for statbus-app/worker/db/proxy from docker image inspect (Docker's records, not log greps), wired into 0-happy-install.sh (after assert_systemd_active, no step renumbering per dolphin's 514 constraint) and 0-happy-upgrade.sh. ./dev.sh test-harness green (tmp/392-test-harness.log). Real-fleet proof still owed by a fleet run.

- **CI (2c5fca659):** Go Test, Fast Tests, Harness Selftest, Images, app build & lint, CodeQL all success. Harness Selftest failed on e65fe668a (the offline happy-install selftest mocks assertions.sh and the new assertion was undefined there); fixed by stubbing it in test/install-recovery/tests/happy-install-test.sh (2c5fca659), verified locally before push.
- **AC6:** go test ./cmd green locally (tmp/392-green.log) and in CI; fast suite green in CI (Fast Tests). Old AC4 withdrawn by owner.

### Reviewed by rabbit (2026-10-20 19:42)
- **Commits** e65fe668a and 2c5fca659 by worker piglet (k3-256k). CI: Go Test and Harness Selftest passed on both.
- **Design followed:** cli/cmd/build_identity.go, where releaseTagPattern ^v[0-9]+\.[0-9]+\.[0-9]+(-rc\.[0-9]+)?$ against the version ldflag is the one answer. cli/cmd/service_up_args.go has the image check behind an injectable seam (config --images, image inspect, pull). startBuildsFromSource is gone, including in install.go's runPullImages.
- **Red/green:** tmp/392-red.log (the tests fail to build against the old code: applyBuildVisibility undefined), tmp/392-green.log (cmd ok).
- **Help, observed by hand:**
  - A source build (v2026.10.3-45-g…) shows Operations and Development.
  - A release build (stamped v2026.10.3, tmp/sb-release-probe) shows Operations only and ends with "Development commands are hidden on a release install; './sb help --all' lists them."
  - `help --all` on the release build lists both groups, and `migrate --help` still works.
- **AC5:** assert_service_images_pulled_from_registry in test/install-recovery/lib/assertions.sh reads RepoDigests from Docker's record. It is wired into 0-happy-install and 0-happy-upgrade and passes in the harness selftest; it is proven when the next candidate's smoke runs it.

AC5 real LXD evidence: rc.03 0-happy-install job 122549573505 verified app, worker, db and proxy all carry ghcr.io registry digests. rc.02 0-happy-upgrade job 122540983899 independently verified the same four images after upgrade. Both scenarios actually passed.
<!-- SECTION:NOTES:END -->
