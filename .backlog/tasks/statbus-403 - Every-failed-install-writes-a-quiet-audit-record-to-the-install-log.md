---
id: STATBUS-403
title: Every failed installation writes one quiet audit record to the install log
status: In Progress
assignee: []
created_date: '2026-09-24 15:35'
updated_date: '2026-09-24 18:42'
labels:
  - release-bug
  - install
  - logging
dependencies:
  - STATBUS-402
priority: medium
type: bug
ordinal: 356000
---

## Status 2026-09-24

**In Progress.** `8543f493a`, `373d15fc3`: `cli/cmd/install.go` and `support.go` move internal failure diagnostics to the install/support log, with plain terminal remedies. #1-3 not yet proved as written: `cli/cmd/install_failure_audit_test.go` is absent, so exactly-once and no-credential properties remain unverified. **Remaining:** assert one private audit record at preflight and post-start failure and a plain recovery-only terminal result.

Baseline: `origin/master` at `373d15fc3`. Criterion disposition and remaining positive targets are above; the acceptance criteria below remain authoritative. An authored but unrun VM scenario is **proof pending**, not met.

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Each failed installation writes exactly one consistently named audit record to the install log and no audit wording to the terminal. The record contains no credentials. The terminal instead prints the positive recovery outcome defined by STATBUS-402: what to fix, the complete rerun command, and the support-file path when applicable.

## Evidence, 2026-09-24

Finland terminal output duplicated internal `FAILED_INSTALL_HAS_AUDIT_TRAIL` wording on separate failures (`/Users/jhf/ssb/statbus/tmp/finland-transcript-2-actual.txt:58-65,114-124`). Successful installation records completion in an upgrade row (`cli/cmd/install.go:2938-3039` at master `7a9cf707e`), while `upgradeRowID == 0` applies only to failures before that write (`cli/cmd/install.go:682-692` at master `7a9cf707e`).
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 `new: cli/cmd/install_failure_audit_test.go::TestPreflightFailureWritesOneAuditRecord` observes exactly one install-log record, zero terminal copies, and no fixture credential.
- [ ] #2 `new: cli/cmd/install_failure_audit_test.go::TestStepFailureWritesOneAuditRecord` observes the same once-only and zero-credential properties after work begins.
- [ ] #3 `new: cli/cmd/install_failure_audit_test.go::TestFailureTerminalShowsRecoveryOutcome` observes the plain fix, complete rerun command, and support-file path instead of audit vocabulary.
<!-- AC:END -->
