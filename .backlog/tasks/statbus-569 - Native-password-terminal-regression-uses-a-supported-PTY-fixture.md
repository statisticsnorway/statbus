---
id: STATBUS-569
title: Native password terminal regression uses a supported PTY fixture
status: Done
assignee: []
created_date: '2026-11-07T22:23:00Z'
updated_date: '2026-11-07T22:46:00Z'
labels:
  - cli
  - testing
  - release
dependencies: []
priority: high
type: bug
ordinal: 507204
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Native ./dev.sh lint on macOS exposes SA1019 in cli/cmd/install_password_ptsname_darwin_test.go: its hand-written real-PTY fixture calls deprecated unix.SYS_IOCTL. The same command's three 579 caller findings are fixed separately. Preserve the actual terminal output-processing/password-mode assertions and remove duplicated raw platform setup through a pinned test-only PTY wrapper. This is existing native validation debt discovered during final release verification, to be fixed now rather than suppressed or deferred. RED logs: tmp/579-lint-red.log and tmp/579-lint-native-after.log.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 The real pseudo-terminal password-mode regression passes on macOS without skipping its output-processing and restore assertions.
- [x] #2 Native Go lint passes without suppressing the deprecated Darwin syscall finding, and Linux terminal coverage remains passing.
- [x] #3 The pinned PTY dependency is imported only by tests, changes are committed and pushed, and exact-SHA CI is green.
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
2026-11-07 22:27Z: GREEN95b966a5c replaces duplicated Linux/Darwin raw PTY naming helpers with pinned github.com/creack/pty v1.1.24, imported only from the terminal test. Existing output-processing, no-echo/no-canonical-input and restore assertions remain. Non-destructive standalone real-PTY prototype passes (tmp/569-pty-prototype.log). Actual Darwin TestPasswordRawModeKeepsLineEndings passes without skip (worker and independent coordinator logs tmp/569-terminal-darwin.log and tmp/569-terminal-darwin-root.log). Coordinator independently runs the same real Linux PTY test in existing local golang:1.26-alpine with network disabled and read-only source/module mounts: PASS0.007s, no skip, tmp/569-terminal-linux-root.log. Native ./dev.sh lint goes from existing SA1019 RED in tmp/579-lint-native-after.log to 0 issues across31packages (worker tmp/569-lint-native-green.log and independent tmp/569-lint-native-root.log). Focused command race tests pass1.809s in tmp/569-cmd-focused-race.log. Production cmd dependency closure excludes the PTY package, saved tmp/569-production-dependencies.json. AC1/2 verified. AC3 and Done await push plus exact-SHA CI. No production behavior or host data changed.

2026-11-07 22:45Z: AC3 verified at pushed source 929fe787c2ab323d3a8c6d013bb9864fbec7bd67, now tagged v2026.11.2-rc.04 at the identical commit. Exact-source GitHub Actions status=completed/conclusion=success: Go Test 42420697650, Harness Selftest 42420697596, app build & lint 42420697689, Images 42420697560, Push on master 42420697128 and Fast Tests 42421034527 (run name explicitly exercised-sha=929fe787c2ab323d3a8c6d013bb9864fbec7bd67). The real Darwin/Linux PTY checks and production dependency closure proof in the previous note remain the behavioral acceptance evidence. All three criteria are satisfied, so STATBUS-569 is Done. This closes only 569: the newly tagged RC's release/fleet gates and 579 host/577 browser acceptance are still running or pending, not declared passed.
<!-- SECTION:NOTES:END -->
