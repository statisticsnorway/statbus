---
id: STATBUS-537
title: 'One version: published scripts state and install the release they belong to'
status: In Progress
assignee: []
created_date: '2026-10-30T08:39:00Z'
updated_date: '2026-10-30T09:37:00Z'
labels:
  - release
  - installer
dependencies: []
priority: high
type: bug
ordinal: 463204
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
### North Star
The StatBus release tag is the only version. Every published script states the release it belongs to. The installer stays flexible: it may install another release, and then says so.

### Zoom out
setup.sh, install.sh and uninstall.sh travel as release assets, and statbus.org serves the latest stable's copies (STATBUS-505). setup.sh printed a made-up SCRIPT_VERSION="1.0.0". install.sh did not say which release it belongs to. Owner's design (2026-10-30): keep it simple, no second version system, and installing another version stays allowed.

### Zoom in
Found on the Uganda run, 2026-10-30: the setup banner showed "Version: 1.0.0" while the script was v2026.10.5.
Design:
- Each of the three scripts has one line, STATBUS_RELEASE="@STATBUS_RELEASE@". ops/release/stamp-release-scripts.sh <tag> <dist> copies them into dist with the tag substituted, and refuses a non-release tag or a script without exactly one such line. release.yaml's staging step calls it.
- Banners: setup prints "StatBus: <tag>"; install.sh prints "StatBus installer <tag>"; uninstall.sh prints "StatBus uninstaller <tag>". An unstamped git copy prints "development copy (not a release)". SCRIPT_VERSION is removed.
- install.sh's choice of version is unchanged (default latest stable, --version, --channel). When a stamped installer installs a different release it prints "This is the <tag> installer; it installs <version>."
- Out of scope: binding the installer to its own release; changing setup's next-step command.
A draft implementation is in tmp/537-draft.patch (apply with git apply).

### Closing review
- **Memory:** none. **Documentation:** the STATBUS_RELEASE comments in the scripts and the release.yaml step. **Cleanup:** SCRIPT_VERSION removed.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 ops/release/stamp-release-scripts.sh stamps the tag into setup-ubuntu-lts.sh, install.sh and uninstall.sh, refuses a non-release tag and a script without exactly one placeholder line; release.yaml's staging step uses it
- [x] #2 Each stamped script's banner prints the tag; an unstamped copy prints development copy (not a release); SCRIPT_VERSION is gone
- [x] #3 A stamped install.sh whose resolved version differs prints 'This is the <tag> installer; it installs <version>.' and nothing extra when they match; version selection is otherwise unchanged
- [x] #4 test/install-recovery/tests/release-script-stamp-test.sh passes: stamps scratch copies and checks all three banners show the tag and the git copies say development copy; it fails against the pre-fix scripts and runs in Harness Selftest
- [ ] #5 The next released setup.sh, install.sh and uninstall.sh fetched from statbus.org print that release's tag
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
STATBUS-537 implemented and green.

Commits:
- 7b6be9075cc8f8978aa46cc163470f2ac1a09583 release: STATBUS-537 published scripts state their release (first CI run went red, diagnosed below)
- 553da4667d8b6f6c4bc839bffea015dabcc41802 release: STATBUS-537 keep the installer banner out of machine-readable seams (final, CI fully green)

CI on 553da4667d8b6f6c4bc839bffea015dabcc41802 (gh run list --commit, status/conclusion):
- Harness Selftest 41034032991 success
- Go Test 41034032816 success
- app build & lint 41034033067 success
- Images 41034032952 success
- CodeQL 41034030908 success
- Notify cloud services 41034032826 success
First attempt (7b6be9075) red: Harness Selftest 41032684281 failed in install-pull-failure-test.sh (pure classification stdout got the banner line) and Go Test 41032684240 failed TestRerunCommandPreservesInvocationOptions (sourced prefix got the banner before the saved command). Fixed by keeping the banner out of the STATBUS_INSTALL_TEST_CLASSIFY_PULL pure seam and by letting the rerun test accept the banner as the first line before asserting the saved command; no assertion was weakened and the saved command itself stays banner-free.

Red/green for test/install-recovery/tests/release-script-stamp-test.sh (logs in tmp/):
- Red: tmp/test-537-red.log, exit 1, 12 FAIL lines. Built a scratch tree from git show HEAD:install.sh, HEAD:uninstall.sh, HEAD:ops/setup-ubuntu-lts.sh plus the real stamper; the stamper refuses the pre-fix scripts and no banner says the tag or development copy.
- Green: tmp/test-537-green.log, exit 0, 'release script stamp test: PASS'.

AC3 observed manually (tmp/test-537-ac3.log): stamped v2026.10.5 installer with --version v2026.10.5 prints only 'StatBus installer v2026.10.5' (no extra line); with --version v2026.01.1 prints 'This is the v2026.10.5 installer; it installs v2026.01.1.'.

Other verification: all test/install-recovery/tests/setup-*.sh pass; fresh-installer-test.sh and happy-install-test.sh pass; install-git-errors/fetch and install-pull-failure pass (install-git-errors locally needs docker and refused at the docker preflight on this Mac, but passed in CI run 41032684281). bash -n clean on install.sh, uninstall.sh, ops/setup-ubuntu-lts.sh, ops/release/stamp-release-scripts.sh and the new test; both edited workflows parse as YAML.

AC5 (published statbus.org scripts show the next release's tag) needs a release and is left to the coordinator.
<!-- SECTION:NOTES:END -->
