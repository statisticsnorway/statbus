---
id: STATBUS-396
title: Git failures show Git's useful error text with every secret redacted
status: In Progress
assignee: []
created_date: '2026-09-24 16:44'
updated_date: '2026-10-15 20:09'
labels:
  - release-bug
  - cli
  - error-handling
  - security
dependencies: []
priority: medium
type: task
ordinal: 86
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
### North Star
When a Git command fails during install or release, the operator sees Git's own useful message (authentication failed, missing ref, host not found) with every secret replaced by `[REDACTED]`.

### Zoom out
Two failure modes pull in opposite directions. Swallowing Git's output leaves the operator guessing ("exit status 128"). Printing it raw can leak a token or a credential-bearing URL into the terminal, the install log and the support file. The answer is one redactor, applied at the single point where Git output is captured, before it is wrapped into an error or written anywhere. It removes the resolved token, its base64 forms, Authorization header values and `user:password@` URL parts, while Git's own diagnostic text survives. Release code and installer code share that redactor without the installer depending on the release engine.

### Zoom in
- **Finding, 2026-09-24:** child-process output was captured with `CombinedOutput` and wrapped into errors unfiltered (`cli/cmd/install.go`, `cli/cmd/db.go` then).
- **Shipped:** `1e96d380f` (release Git calls keep redacted stderr, v2026.09.3); merge `9d8312673` (2026-10-01, in v2026.10.1): neutral `cli/internal/redact` holds the one implementation, `cli/internal/gitexec` is the installer's Git adapter (`3ae075c9c`, `c9d164361`), and the redactor now strips URL userinfo too.
- **Proof:** `TestAuthenticationFailurePreservesMessageAndRedactsSecret`, `TestMissingRefPreservesMessage`, `TestNetworkFailurePreservesMessageAndRedactsURLCredentials` (`cli/internal/gitexec/errors_test.go`); `test/install/install-git-errors-test.sh` drives the three failures through the public installer and checks terminal and install log. All green locally 2026-10-15 (`tmp/vet/396-install-git-errors.log`).
- **Not in CI:** nothing under `.github/workflows` or `dev.sh` runs `test/install/*.sh`, so the installer-level test only runs when someone runs it by hand. `cli/internal/redact` has no tests of its own; it is exercised through `gitexec` and `release`.

### Closing review
- **Memory:** none needed.
- **Documentation:** none needed.
- **Cleanup:** none.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 An authentication failure through a credential-bearing URL keeps `fatal: Authentication failed` and shows `[REDACTED]` with no secret substring left, in terminal and log (`TestAuthenticationFailurePreservesMessageAndRedactsSecret`)
- [x] #2 A missing ref keeps `fatal: couldn't find remote ref <ref>` in terminal and log (`TestMissingRefPreservesMessage`)
- [x] #3 A network failure keeps `Could not resolve host` and redacts URL credentials (`TestNetworkFailurePreservesMessageAndRedactsURLCredentials`)
- [x] #4 The three failures through the public installer show the same in terminal and install log (`test/install/install-git-errors-test.sh`)
- [ ] #5 [Owner] Decide whether `test/install/*.sh` runs in a CI workflow (for example Harness Selftest) or stays manual, and record it in Implementation Notes. CI: add the wiring as a new criterion. Manual: check this and set Done.
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
### Evidence
- **AC1-3:** green locally on master, 2026-10-15.
- **AC4:** green locally 2026-10-15, `tmp/vet/396-install-git-errors.log`.
- **AC5:** open; `rg "test/install/" .github dev.sh` finds no runner.
- **History:** the 2026-10-01 implementation and review notes are in Git history.
<!-- SECTION:NOTES:END -->
