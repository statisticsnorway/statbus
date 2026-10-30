---
id: STATBUS-275
title: >-
  preflight-ride-verbosity: the exempt-ride check lists every justifying file
  per gate — compress to a count, the whitelist already defines exemption
status: Done
assignee: []
created_date: '2026-08-27 13:51'
updated_date: '2026-08-27 19:39'
labels:
  - release
dependencies: []
priority: medium
type: enhancement
ordinal: 268000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
King's feedback at the rc.10 preflight (2026-08-27): the "Files changed since (all exempt per ops/release/ci-exempt-paths.txt):" listing repeats the full file enumeration under EACH riding gate (go-test, app-build-lint, fast-tests — three times in one preflight), and it is too much: the whitelist already defines what counts as exempt.

The change, in cli/cmd/release.go's ride-printing (~:1686): keep the ride LOUD about what matters — the tested commit, the run URL, and that the gate is riding — but replace the per-file enumeration with a count line: "N file(s) changed since, all exempt per ops/release/ci-exempt-paths.txt". The original design language ("naming the ride target and every justifying file", ops/release/ci-exempt-paths.txt:6) softens deliberately by the King's ruling — update that header comment to match the new behavior so prose and code agree.

Check and retarget any test asserting the listing (release_ci_exempt_ride_test.go and the ancestor-verdict tests) — retarget, never weaken: the properties (ride is printed, target named, exemption source cited) all stay; only the enumeration goes.

WHAT IS ACHIEVED: the preflight says everything load-bearing in one line per riding gate, and a board-heavy day no longer scrolls the operator past their own gates.
<!-- SECTION:DESCRIPTION:END -->

## Comments

<!-- COMMENTS:BEGIN -->
author: foreman
created: 2026-08-27 19:39
---
CLOSED with live acceptance evidence: the fix landed during the rc.10 cycle (release.go — exempt-ride justification compressed to a count, the exemption cited via ops/release/ci-exempt-paths.txt; see the comment near release.go:1706), and tonight's rc.11 preflight (2026-08-27, the King's own cut output) shows exactly the intended form: '5 file(s) changed since, all exempt per ops/release/ci-exempt-paths.txt' — a count line, no per-file listing. The ticket lagged the landing; closing on the King's cut output as the acceptance run.
---
<!-- COMMENTS:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
The preflight's exempt-ride checks no longer list every justifying file per gate — the justification is compressed to a count with the exemption source cited (ops/release/ci-exempt-paths.txt), since the whitelist itself defines exemption. Landed during the rc.10 cycle; accepted live in the King's rc.11 cut output ('5 file(s) changed since, all exempt per ops/release/ci-exempt-paths.txt').
<!-- SECTION:FINAL_SUMMARY:END -->
