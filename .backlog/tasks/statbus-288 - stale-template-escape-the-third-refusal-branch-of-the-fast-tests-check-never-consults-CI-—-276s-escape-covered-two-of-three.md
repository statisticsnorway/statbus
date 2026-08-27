---
id: STATBUS-288
title: >-
  stale-template-escape: the third refusal branch of the fast-tests check never
  consults CI — 276's escape covered two of three
status: To Do
assignee: []
created_date: '2026-08-27 18:28'
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
