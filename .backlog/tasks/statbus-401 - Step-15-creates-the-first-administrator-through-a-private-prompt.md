---
id: STATBUS-401
title: Step 15 creates the first administrator through a private prompt
status: In Progress
assignee: []
created_date: '2026-09-24 15:35'
updated_date: '2026-09-24 18:42'
labels:
  - release-bug
  - install
  - users
  - security
dependencies: []
priority: high
type: bug
ordinal: 354000
---

## Status 2026-09-24

**In Progress.** `2aea9e733`, `373d15fc3`: `cli/cmd/install_admin_prompt_test.go::TestPasswordMismatchRetriesWithoutDisclosure` satisfies #2; `0-interactive-admin-password.sh` and `0-happy-install.sh` are authored for #1, #3-4, but real-VM hidden-input/login and log-secrecy proofs are pending. **Remaining:** run both VM paths and verify password-free terminal, install log, and support log with successful login.

Baseline: `origin/master` at `373d15fc3`. Criterion disposition and remaining positive targets are above; the acceptance criteria below remain authoritative. An authored but unrun VM scenario is **proof pending**, not met.

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Interactive step 15 asks for administrator email, name, and two matching password entries with hidden typing, then creates the administrator. Unattended installation retains configured-file creation. Terminal, install log, and support log contain no password value.

## Evidence, 2026-09-24

Finland step 15 stopped because `.users.yml` was absent (`/Users/jhf/ssb/statbus/tmp/finland-transcript-2-actual.txt:53-65`). After the file was supplied, the step printed a password-bearing result column (`/Users/jhf/ssb/statbus/tmp/finland-transcript-2-actual.txt:99-112`). Step 15 invokes user creation at `cli/cmd/install.go:2567-2570`, and file handling is at `cli/cmd/install.go:1278-1307`, both at master `7a9cf707e`.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 `new: test/install-recovery/scenarios/0-interactive-admin-password.sh` observes two hidden matching password entries, creates the administrator, and completes installation.
- [ ] #2 `new: cli/cmd/install_admin_prompt_test.go::TestPasswordMismatchRetriesWithoutDisclosure` supplies mismatched entries and observes a plain retry with neither value disclosed.
- [ ] #3 `new: test/install-recovery/scenarios/0-interactive-admin-password.sh` proves the fixture password is absent from terminal, install log, and support log, then signs in successfully through `/rest/rpc/login`.
- [ ] #4 `test/install-recovery/scenarios/0-happy-install.sh` proves unattended configured-file user creation still completes and also contains no fixture password in terminal, install log, or support log.
<!-- AC:END -->
