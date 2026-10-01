---
id: STATBUS-396
title: Git failures show Git's useful error text with every secret redacted
status: In Progress
assignee: []
created_date: '2026-09-24 16:44'
updated_date: '2026-09-29 08:04'
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
When a Git command fails, terminal and log output retain Git's actionable authentication, missing-reference, or network text while replacing tokens, passwords, and credential-bearing URL components with `[REDACTED]`.

## Evidence, 2026-09-24

Master commonly captures child-process output with `CombinedOutput` and includes it in wrapped errors, for example `cli/cmd/install.go:1646-1649` and `cli/cmd/db.go:290-292` at `7a9cf707e`. The permitted representative fixture texts are recorded by the named tests below: `fatal: Authentication failed`, `fatal: couldn't find remote ref <ref>`, and `fatal: unable to access <url>: Could not resolve host`.
<!-- SECTION:DESCRIPTION:END -->

## Status 2026-09-24

**In Progress.** `1e96d380f`: `cli/internal/release/github_auth.go:26-45,107-120` preserves redacted Git stderr for release Git calls and `github_auth_test.go` exercises token redaction. #1-4 as written are not yet met: `cli/internal/gitexec/errors_test.go` and installer-level `test/install/install-git-errors-test.sh` do not exist. **Remaining:** prove authentication, missing ref, and DNS failures retain Git's text and redact secrets in both terminal and install log.

Baseline: `origin/master` at `373d15fc3`. Criterion disposition and remaining positive targets are above; the acceptance criteria below remain authoritative. An authored but unrun VM scenario is **proof pending**, not met.

## Acceptance Criteria

- [x] #1 `new: cli/internal/gitexec/errors_test.go::TestAuthenticationFailurePreservesMessageAndRedactsSecret` sends a credential-bearing URL and observes `fatal: Authentication failed` plus `[REDACTED]` in terminal and log output, with no fixture-secret substring surviving.
- [x] #2 `new: cli/internal/gitexec/errors_test.go::TestMissingRefPreservesMessage` observes `fatal: couldn't find remote ref <ref>` in terminal and log output.
- [x] #3 `new: cli/internal/gitexec/errors_test.go::TestNetworkFailurePreservesMessageAndRedactsURLCredentials` observes `Could not resolve host` and `[REDACTED]` in both outputs with no fixture-secret substring surviving.
- [x] #4 `new: test/install/install-git-errors-test.sh` exercises the three named Git failures through the installer and verifies the same terminal and install-log assertions.

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Audit after v2026.09.3 (2026-09-29): v2026.09.3: release-package Git errors carry Git's text with secrets redacted (9fcbe2ae6, 6442f2b8a). The installer path is untouched: cli/internal/gitexec and the AC1-4 tests do not exist.

2026-10-01: Added `cli/internal/gitexec` as the installer Git execution adapter. It captures Git stdout/stderr, passes both through the existing `release.RedactGitHubCredentials` implementation, and only then writes terminal/log output or wraps the command error. The shared release redactor now also removes credential-bearing URL userinfo. Installer Git commands use the adapter, the three named unit tests cover authentication/missing-ref/DNS diagnostics, and `test/install/install-git-errors-test.sh` proves the same text and redaction through `sb install`. `go build`, `go vet`, and `go test ./cmd/ ./internal/...` all pass.

2026-10-01 review correction: Moved the single redaction implementation into neutral `cli/internal/redact`, with release and installer adapters supplying their resolved token without crossing the STATBUS-352 release-engine boundary. Added a pure/local `install.sh` seam that writes through the public installer's real `~/statbus/tmp/install-last-run-output.txt`; the install test invokes the public script and inspects that file independently from its terminal capture rather than manufacturing two copies of one pipeline.
<!-- SECTION:NOTES:END -->
