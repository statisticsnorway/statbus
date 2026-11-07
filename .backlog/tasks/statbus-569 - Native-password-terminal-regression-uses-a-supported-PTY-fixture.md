---
id: STATBUS-569
title: Native password terminal regression uses a supported PTY fixture
status: In Progress
assignee: []
created_date: '2026-11-07T22:23:00Z'
updated_date: '2026-11-07T22:27:00Z'
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
- [ ] #3 The pinned PTY dependency is imported only by tests, changes are committed and pushed, and exact-SHA CI is green.
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
2026-11-07 22:27Z: GREEN95b966a5c replaces duplicated Linux/Darwin raw PTY naming helpers with pinned github.com/creack/pty v1.1.24, imported only from the terminal test. Existing output-processing, no-echo/no-canonical-input and restore assertions remain. Non-destructive standalone real-PTY prototype passes (tmp/569-pty-prototype.log). Actual Darwin TestPasswordRawModeKeepsLineEndings passes without skip (worker and independent coordinator logs tmp/569-terminal-darwin.log and tmp/569-terminal-darwin-root.log). Coordinator independently runs the same real Linux PTY test in existing local golang:1.26-alpine with network disabled and read-only source/module mounts: PASS0.007s, no skip, tmp/569-terminal-linux-root.log. Native ./dev.sh lint goes from existing SA1019 RED in tmp/579-lint-native-after.log to 0 issues across31packages (worker tmp/569-lint-native-green.log and independent tmp/569-lint-native-root.log). Focused command race tests pass1.809s in tmp/569-cmd-focused-race.log. Production cmd dependency closure excludes the PTY package, saved tmp/569-production-dependencies.json. AC1/2 verified. AC3 and Done await push plus exact-SHA CI. No production behavior or host data changed.
<!-- SECTION:NOTES:END -->
