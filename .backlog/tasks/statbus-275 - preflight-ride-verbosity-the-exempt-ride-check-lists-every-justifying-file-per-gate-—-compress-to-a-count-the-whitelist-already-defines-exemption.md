---
id: STATBUS-275
title: >-
  preflight-ride-verbosity: the exempt-ride check lists every justifying file
  per gate — compress to a count, the whitelist already defines exemption
status: To Do
assignee: []
created_date: '2026-08-27 13:51'
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
