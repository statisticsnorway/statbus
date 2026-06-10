---
id: STATBUS-024
title: >-
  ci-go-test: no workflow runs `go test` — 30+ cli/internal Go tests (inject,
  upgrade) never execute in CI
status: To Do
assignee: []
created_date: '2026-06-10 20:40'
labels:
  - ci
  - test
  - tech-debt
dependencies: []
priority: medium
ordinal: 24000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
SIDE-FINDING (architect, 2026-06-10, while building the RC-readiness assessment). NO CI workflow, dev.sh path, or git hook runs `go test` — verified across all ~31 workflows. So the 30+ `cli/internal/**/*_test.go` (including cli/internal/inject/inject_test.go and the cli/internal/upgrade/*_test.go suite) are NEVER executed in CI — they're orphaned. A Go test can rot/break silently and nothing catches it.

IMMEDIATE relevance: STATBUS-022 adds an inject_test.go unit test for the one-shot kill, and STATBUS-023's design relies on a round-trip contract (real ReadFlagFile parses the fabricated flag). Both lose their teeth-in-CI if `go test` never runs. (022's contract is partially saved because the inject behavior is also exercised by the harness scenarios; 023's generator self-checks in-process at fabrication time. But the unit tests themselves still don't run.)

WORK: add `cd cli && go test ./...` (or at least `./internal/...`) to the fast CI lane (e.g. .github/workflows/fast-tests.yaml or test-hardening.yaml — whichever is the cheap in-runner lane). Expect to first triage any of the 30+ orphaned tests that have rotted from never running (fix or quarantine with a reason). Then it becomes a real gate. Architect flagged this as 023-adjacent. Not blocking the RC cut (the cut doesn't gate on go test); it's a real coverage gap for the Go layer (incl. the upgrade/recovery code the 017 work lives in).
<!-- SECTION:DESCRIPTION:END -->
