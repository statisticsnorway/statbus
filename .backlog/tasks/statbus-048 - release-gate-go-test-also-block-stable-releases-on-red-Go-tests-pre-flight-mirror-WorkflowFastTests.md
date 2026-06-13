---
id: STATBUS-048
title: >-
  release-gate-go-test: also block stable releases on red Go tests (pre-flight,
  mirror WorkflowFastTests)
status: To Do
assignee: []
created_date: '2026-06-13 11:48'
labels:
  - ci
  - test
  - release
dependencies: []
priority: low
ordinal: 48000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Follow-up from STATBUS-024 (engineer, 2026-06-13). The per-change gate (.github/workflows/go-test.yaml, commit 5b4e518bc) blocks PRs + master on a red Go test. This adds defense-in-depth: wire go-test-green into the stable-release PRE-FLIGHT gate so a red Go test also blocks cutting a stable release — mirror release.WorkflowFastTests in cli/internal/release/workflow_check.go.

Left out of 024 to keep scope tight + avoid touching the release-gate code. LOW priority: the per-change gate already catches red Go tests before they could reach a release branch, so this is belt-and-suspenders, not a hole.
<!-- SECTION:DESCRIPTION:END -->
