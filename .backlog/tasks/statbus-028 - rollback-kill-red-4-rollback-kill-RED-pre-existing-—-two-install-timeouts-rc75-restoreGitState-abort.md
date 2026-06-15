---
id: STATBUS-028
title: >-
  rollback-kill-red: 4-rollback-kill RED (pre-existing) — two install timeouts +
  rc=75 restoreGitState abort
status: In Progress
assignee:
  - mechanic
created_date: '2026-06-11 07:48'
updated_date: '2026-06-15 13:20'
labels:
  - install-recovery
  - harness
dependencies: []
priority: medium
ordinal: 28000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Run 27306718138 @ cd2f5d51f: 4-rollback-kill FAIL (pre-existing red, not attempted tonight). Log: rc=137 at 4-rollback-kill.sh:153 (install-first.sh) AND :201 (install-second.sh) — both install attempts timed out — plus rc=75 at vm-bootstrap.sh:575 (restoreGitState abort). This is the C9 multi-kill scenario; the architect classified it as a pre-existing harness issue (multi-kill timing). Likely shares the restoreGitState root with STATBUS-026 (checkout-kill). HARNESS, 0 product. Does NOT block the RC cut. Architect/engineer-sized.
<!-- SECTION:DESCRIPTION:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
COMMITTED 3b986a2d0 (pushed). Foreman verified: os.Exit(75) at service.go:5309 is the documented 'UPGRADE FAILED, ROLLED BACK' terminal exit after a COMPLETED rollback (git/binary/db restored, services up). The scenario's outcome-B branch expects exactly that, so tolerating rc=75 on the third (recovery-completion) install — the established 2-preswap-checkout-kill:215 idiom — is correct; without it set -e mislabels a successful rollback as a 'restoreGitState abort'. HARNESS-only, 1-line + comment. GREEN pending the comprehensive matrix harness run (operator drives once 027/029 + 031 scenario land).
<!-- SECTION:NOTES:END -->
