---
id: STATBUS-010
title: >-
  Fix stale "sha-HEXHEX" in upgrade version-validator error message
  (upgrade.go:135)
status: Done
assignee: []
created_date: '2026-06-07 21:54'
updated_date: '2026-06-30 20:40'
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
- [x] #1 The validator's actual accepted version contract is confirmed (CalVer-only vs CalVer+SHA)
- [x] #2 upgrade.go:135 error message corrected to match reality (no stale sha-HEXHEX)
- [x] #3 Decision recorded on whether CalVer-only is intentional or schedule should accept SHAs
<!-- AC:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Resolved by intervening work (rc.63 + the STATBUS-086/108 register-schedule rework) — no diff needed. Engineer investigated; foreman independently verified all three pieces of evidence:

AC#1 (contract confirmed): the accepted upgrade-target contract is {release tag vYYYY.MM.patch[-suffix] | 8-char commit_short | 40-char commit_sha}, git-resolved to the canonical commit via the typed resolver (cli/internal/upgrade/commit.go:316; cmd/upgrade.go:18-19 register, :65-66 schedule).

AC#2 (no stale sha-HEXHEX): CONFIRMED gone. `rg HEXHEX` repo-wide returns zero matches. The file the ticket cited (cli/internal/upgrade/upgrade.go:135) no longer exists — reorganized into commit.go/github.go/service.go in rc.63. Every current operator-facing version-format error is accurate.

AC#3 (decision recorded): the ticket's premise ("schedule cannot accept a bare commit SHA; CalVer-only") was inverted by rc.63. `schedule` now INTENTIONALLY accepts commit SHAs (short + full) — documented working examples at cmd/upgrade.go:74-76 (`sb upgrade schedule abc1234f`). Decision: SHAs are accepted; not CalVer-only.

No code change. Engineer correctly did NOT fabricate a no-op edit. Closed as resolved-by-intervening-work.
<!-- SECTION:FINAL_SUMMARY:END -->
