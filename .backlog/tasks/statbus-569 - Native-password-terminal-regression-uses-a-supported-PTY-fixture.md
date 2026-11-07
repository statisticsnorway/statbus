---
id: STATBUS-569
title: Native password terminal regression uses a supported PTY fixture
status: In Progress
assignee: []
created_date: '2026-11-07T22:23:00Z'
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
- [ ] #1 The real pseudo-terminal password-mode regression passes on macOS without skipping its output-processing and restore assertions.
- [ ] #2 Native Go lint passes without suppressing the deprecated Darwin syscall finding, and Linux terminal coverage remains passing.
- [ ] #3 The pinned PTY dependency is imported only by tests, changes are committed and pushed, and exact-SHA CI is green.
<!-- AC:END -->
