---
id: STATBUS-403
title: Every failed installation writes one quiet audit record to the install log
status: Done
assignee: []
created_date: '2026-09-24 15:35'
updated_date: '2026-10-15 19:37'
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

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
### North Star
Every failed installation leaves exactly one plain, credential-free audit line in the install log for support, and the operator's terminal shows only the recovery path.

### Zoom out
Support needs to know that an install failed and how it was classified, even when it failed before any upgrade row existed. The operator needs to know what to do next. These are two audiences, and mixing them is what went wrong: internal audit wording leaked into the terminal, sometimes twice. So the audit record lives only in the install log, is written exactly once per failed run through one reporting boundary, and carries a classification, never raw errors or command arguments that might hold a password. The terminal shows the cause, the fix, the rerun command and the support-file path (STATBUS-402).

### Zoom in
- **Incident, Finland 2026-09-24/25 (v2026.09.2):** the terminal repeated `INVARIANT FAILED_INSTALL_HAS_AUDIT_TRAIL violated (audit-only): install failed with no upgrade row ...` on separate failures (`tmp/finland-transcript-2-actual.txt:58-65,114-124`; also `tmp/finland-transcript-actual.txt`).
- **Shipped:** v2026.09.3 moved the breadcrumb to the install log only (`TestFailedInstallBreadcrumbIsLogOnlyAndPlainlyNamed`). Merge `7f231a5f6` (2026-10-01, in v2026.10.1) routes every returned failure through `reportInstallFailure`, writing exactly one classification-only `install_failed_no_row` record, including failures before the step log exists.
- **Proof:** `TestFailedInstallWritesOneQuietFailClosedRecordAndRealRecoveryOutcome` (`cli/cmd/install_failure_audit_test.go`) drives real `runInstall` preflight and step failures with a fixture credential (`postgres://admin:fixture-password-403@db/statbus`) in the error. It requires exactly one `install_failed_no_row:` line in the log, no credential in it, and the terminal showing cause, rerun command and support path. Green 2026-10-15.

### Closing review
- **Memory:** none needed.
- **Documentation:** none needed.
- **Cleanup:** none.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 A preflight failure writes exactly one `install_failed_no_row` record to the install log, none to the terminal, with no credential in it (`TestFailedInstallWritesOneQuietFailClosedRecordAndRealRecoveryOutcome`, preflight case)
- [x] #2 A failure after work begins does the same (same test, step case)
- [x] #3 The terminal shows the cause, the complete rerun command and the support-file path instead of audit vocabulary (same test; `TestFailedInstallBreadcrumbIsLogOnlyAndPlainlyNamed`)
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
### Evidence
- **AC1-3:** merge `7f231a5f6` (in v2026.10.1); test green locally on master, 2026-10-15.
- **Done:** all criteria met and nothing open.
<!-- SECTION:NOTES:END -->
