---
id: STATBUS-010
title: >-
  Fix stale "sha-HEXHEX" in upgrade version-validator error message
  (upgrade.go:135)
status: To Do
assignee: []
created_date: '2026-06-07 21:54'
labels:
  - upgrade
  - cli
dependencies: []
references:
  - cli/internal/upgrade/upgrade.go
priority: low
ordinal: 10000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Mechanic flagged this while fixing the migrate-killed-after-commit harness scenario (overnight grind). cli/internal/upgrade/upgrade.go:135 error message reads: "expected vYYYY.MM.PATCH or sha-HEXHEX" — but the sha-HEXHEX form was RETIRED in rc.63. `./sb upgrade schedule` now only accepts CalVer release tags (vYYYY.MM.PATCH) and UPDATEs existing 'available' rows; it cannot schedule a bare/untagged commit SHA. The error message is misleading (suggests sha-HEXHEX works; it doesn't).

This is a PRODUCT change (operator-facing CLI message) — flagged for the King's review rather than auto-fixed overnight. Low-risk text fix once confirmed:
1. Verify the validator's actual accepted contract (CalVer-only? see upgrade.go around :135 + the validate function).
2. Correct the message to reflect it (e.g. "expected vYYYY.MM.PATCH release tag").
3. Optional/bigger question: is CalVer-tag-only intentional, or should schedule also accept commit SHAs for some flows? The install-recovery harness works around it by fabricating the scheduled row directly (the established pattern across the supervised scenarios), so this is not blocking — but worth a deliberate decision.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 The validator's actual accepted version contract is confirmed (CalVer-only vs CalVer+SHA)
- [ ] #2 upgrade.go:135 error message corrected to match reality (no stale sha-HEXHEX)
- [ ] #3 Decision recorded on whether CalVer-only is intentional or schedule should accept SHAs
<!-- AC:END -->
