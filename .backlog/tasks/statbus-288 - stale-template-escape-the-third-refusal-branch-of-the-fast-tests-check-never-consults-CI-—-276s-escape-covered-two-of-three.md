---
id: STATBUS-288
title: >-
  stale-template-escape: the third refusal branch of the fast-tests check never
  consults CI — 276's escape covered two of three
status: Done
assignee: []
created_date: '2026-08-27 18:28'
updated_date: '2026-08-27 18:42'
labels:
  - release
  - ci
dependencies: []
priority: medium
type: bug
ordinal: 281000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Found live during the King's rc.11 preflight (2026-08-27): "Fast tests do not cover latest migrations / Stamp's source-DB version 20260714100527 != HEAD's on-disk max 20260827163000" refused and demanded a local run — while the SAME preflight output showed "✓ fast-tests green at a3988e163536" for the CI workflow at the identical tip.

Root cause: STATBUS-276's drift-oracle escape (driftCoveredByCIGreen) was wired into two of the check's three refusal branches — new-migrations drift (cli/cmd/release.go:356) and expected-file drift (:338) — but the stale-template branch (:308-313, stamp version != on-disk max) predates the pattern and fails hard with no CI consultation.

The escape's ratified argument extends verbatim: CI's fast-tests run rebuilds seed and template FROM SCRATCH at the tested commit, so a green there covers the on-disk max migrations by construction — a strictly stronger oracle than the local stamp's recorded source version. Per 276's principle, the relaxation must validate its inputs more strictly than the guard it bypasses: the escape should require the CI green to be at (or exempt-ride to) HEAD, same as the sibling branches.

Fix shape: wire :308's refusal through driftCoveredByCIGreen with the same printDriftEitherOrRefusal either/or message; a test in release_drift_ci_escape_test.go pinning the new branch. Tonight's occurrence was unblocked the manual way (fresh migrate-and-test fast minting the stamp), so this is principle-fix, not urgent-unblock.

WHAT IS ACHIEVED: no release cut ever again demands a local test run whose verdict CI has already delivered at the same commit — the last of the three refusal branches honors the oracle the other two already trust.
<!-- SECTION:DESCRIPTION:END -->

## Comments

<!-- COMMENTS:BEGIN -->
author: foreman
created: 2026-08-27 18:42
---
LANDED at 85b692a3c after the architect's LAND verdict, with the scope grown by what the fix uncovered. THE RULING (the split is ONE rule, not an inconsistency): an escape's oracle must be the workflow that directly examines the property the branch guards, and the evidence must be stronger than what the branch disputes — a branch that disputes whether an execution happened cannot be satisfied by inherited evidence of one. Hence the staleness branch consults fast-tests (whose green at tip a3988e163 was a real 89/89 execution recording source version 20260827163000 — the exact guarded property), while the file-drift siblings keep pg_regress (their stamp→HEAD drift predates the ride's ancestor→HEAD baseline, so an inherited green legitimately covers them — checked, not assumed). Load-bearing negative pinned by test and RED-verified: a pg_regress green with no fast-tests green REFUSES, because pg_regress greens can be stamp-rides (proven same evening: run 33100320742 rode with zero tests executed and conclusion success). RIDE MECHANISM VERIFIED SOUND, recorded so tonight's alarm never hardens into folklore: the ride at a3988e163 bottomed at minting run 33099747588, a genuine 89/89 execution including 095/096 — no finding against the mechanism. Also in the commit: the go-test determinism fix (clock seam; deadline-before-emission raced wall-clock in a 40ms budget). Follow-ups filed separately: guaranteed first progress line before timeout; six pre-existing gofmt files; STATBUS-285 escalated to gate-integrity standing.
---
<!-- COMMENTS:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
The release preflight's stale-template refusal — the third branch of the fast-tests coverage check, missed by STATBUS-276's escape — now consults CI before demanding a local run, and through the RIGHT oracle: the fast-tests workflow, whose green is a direct execution of the guarded property (suite ran against a template built from HEAD's migrations), never pg_regress, whose green can be a stamp-ride — inherited evidence that a suite passed somewhere earlier, which is precisely the claim staleness disputes. The split between the escape family's oracles is the architect's ratified rule (oracle must directly examine the guarded property), enforced by a RED-verified negative test. Found live when the King's rc.11 cut was refused a local stamp that the Mac's result-file corruption (STATBUS-286) made a lottery to mint, while CI's real 89/89 execution sat green at the same commit. Landed at 85b692a3c together with the go-test clock-injection fix; the ride mechanism itself was chain-verified sound the same evening.
<!-- SECTION:FINAL_SUMMARY:END -->
