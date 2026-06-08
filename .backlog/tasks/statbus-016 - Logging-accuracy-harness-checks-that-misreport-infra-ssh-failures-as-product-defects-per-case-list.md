---
id: STATBUS-016
title: >-
  Logging-accuracy: harness checks that misreport infra/ssh failures as product
  defects (per-case list)
status: In Progress
assignee:
  - operator
created_date: '2026-06-08 16:15'
labels:
  - install-recovery
  - ci
  - logging-accuracy
dependencies: []
references:
  - test/install-recovery/scenarios/3-postswap-archivebackup-resume.sh
  - test/install-recovery/lib/assertions.sh
priority: medium
ordinal: 16000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
King's principle (2026-06-08): if a log leads an inspector to believe there's a product defect and reproduction shows there isn't, the LOGGING isn't accurate enough — the DEFAULT reading of a log line should be the correct one. This is CASE-BY-CASE (no mechanical general pass); each is fixed at the specific log line. This task IS the concrete per-case list (not a policy).

THE OVER-CLAIM PATTERN: a check captures a command's output with a failure fallback sentinel (`|| echo "FAILED"` / `|| echo "0"` / etc.) or a pipefail-mangled value, then an assertion treats the sentinel as a real defect-finding → a FALSE product-defect alarm on what was actually an infra/ssh/check failure. Fix: at that line, keep the command's exit code and the finding SEPARATE — claim a defect only on real evidence (a filename/count); on infra failure log "check could not run (rc=N)".

KNOWN CASES:
1. archivebackup-resume gzip-t check — 3-postswap-archivebackup-resume.sh ~516: `... 2>/dev/null || echo "FAILED"` → `[ -n "$BAD_ARCHIVE" ]` fired "a PARTIAL was published (pre-ATOMIC bug)" on an ssh non-zero (no real partial). Cost ~2h (escalated as a possible product bug). FIXED 384ecd0d0.
2. orphan-count assertion — lib/assertions.sh ~95: `grep -c .` exits 1 on zero + pipefail → `|| echo "0"` doubled → "0\n0" → "orphan backup(s) found" when zero existed. FIXED 8366440d9.
3. C8 / container-restart-kill — DIFFERENT shape (NOT logging inaccuracy): "UPGRADE_DIED_DURING_RESUME, rolled back" was TRUE; the mechanic misread it as a verify-health product bug because the log didn't say "this rollback is correct, by design (Resuming latch)". Fix = a by-design annotation, not a logic change (ties to STATBUS-015). Demonstrates the King's nuance: accurate-but-under-context also fails the "right conclusion without reproducing" test.

OPERATOR SCANNING test/install-recovery/ for more over-claim instances (`||echo`-sentinel → defect-assertion) → results append here, with each classified MISREADABLE vs benign, then fixed at its line.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Operator scan complete: every `||echo`-sentinel / pipefail-mangled assertion site in test/install-recovery/ listed + classified (misreadable-as-defect vs benign)
- [ ] #2 Each MISREADABLE case fixed at its specific line (separate infra-failure from defect-finding; defect-claim only on real evidence)
- [ ] #3 Accurate-but-under-context outcomes (latch rollback, rolled-back-then-recomplete) get a by-design annotation so they don't read as failures
<!-- AC:END -->
