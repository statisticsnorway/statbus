---
id: STATBUS-396
title: Git failures show Git's useful error text with every secret redacted
status: In Progress
assignee: []
created_date: '2026-09-24 16:44'
updated_date: '2026-09-24 18:42'
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

## Status 2026-09-24

**In Progress.** `1e96d380f`: `cli/internal/release/github_auth.go:26-45,107-120` preserves redacted Git stderr for release Git calls and `github_auth_test.go` exercises token redaction. #1-4 as written are not yet met: `cli/internal/gitexec/errors_test.go` and installer-level `test/install/install-git-errors-test.sh` do not exist. **Remaining:** prove authentication, missing ref, and DNS failures retain Git's text and redact secrets in both terminal and install log.

Baseline: `origin/master` at `373d15fc3`. Criterion disposition and remaining positive targets are above; the acceptance criteria below remain authoritative. An authored but unrun VM scenario is **proof pending**, not met.

## Description

When a Git command fails, terminal and log output retain Git's actionable authentication, missing-reference, or network text while replacing tokens, passwords, and credential-bearing URL components with `[REDACTED]`.

## Evidence, 2026-09-24

Master commonly captures child-process output with `CombinedOutput` and includes it in wrapped errors, for example `cli/cmd/install.go:1646-1649` and `cli/cmd/db.go:290-292` at `7a9cf707e`. The permitted representative fixture texts are recorded by the named tests below: `fatal: Authentication failed`, `fatal: couldn't find remote ref <ref>`, and `fatal: unable to access <url>: Could not resolve host`.

## Acceptance Criteria

- [ ] #1 `new: cli/internal/gitexec/errors_test.go::TestAuthenticationFailurePreservesMessageAndRedactsSecret` sends a credential-bearing URL and observes `fatal: Authentication failed` plus `[REDACTED]` in terminal and log output, with no fixture-secret substring surviving.
- [ ] #2 `new: cli/internal/gitexec/errors_test.go::TestMissingRefPreservesMessage` observes `fatal: couldn't find remote ref <ref>` in terminal and log output.
- [ ] #3 `new: cli/internal/gitexec/errors_test.go::TestNetworkFailurePreservesMessageAndRedactsURLCredentials` observes `Could not resolve host` and `[REDACTED]` in both outputs with no fixture-secret substring surviving.
- [ ] #4 `new: test/install/install-git-errors-test.sh` exercises the three named Git failures through the installer and verifies the same terminal and install-log assertions.
