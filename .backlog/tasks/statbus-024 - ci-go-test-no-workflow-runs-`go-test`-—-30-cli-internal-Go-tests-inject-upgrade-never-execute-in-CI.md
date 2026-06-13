---
id: STATBUS-024
title: >-
  ci-go-test: no workflow runs `go test` — 30+ cli/internal Go tests (inject,
  upgrade) never execute in CI
status: In Progress
assignee:
  - engineer
created_date: '2026-06-10 20:40'
updated_date: '2026-06-13 11:42'
labels:
  - ci
  - test
  - tech-debt
dependencies: []
priority: high
ordinal: 24000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
SIDE-FINDING (architect, 2026-06-10, while building the RC-readiness assessment). NO CI workflow, dev.sh path, or git hook runs `go test` — verified across all ~31 workflows. So the 30+ `cli/internal/**/*_test.go` (including cli/internal/inject/inject_test.go and the cli/internal/upgrade/*_test.go suite) are NEVER executed in CI — they're orphaned. A Go test can rot/break silently and nothing catches it.

IMMEDIATE relevance: STATBUS-022 adds an inject_test.go unit test for the one-shot kill, and STATBUS-023's design relies on a round-trip contract (real ReadFlagFile parses the fabricated flag). Both lose their teeth-in-CI if `go test` never runs. (022's contract is partially saved because the inject behavior is also exercised by the harness scenarios; 023's generator self-checks in-process at fabrication time. But the unit tests themselves still don't run.)

WORK: add `cd cli && go test ./...` (or at least `./internal/...`) to the fast CI lane (e.g. .github/workflows/fast-tests.yaml or test-hardening.yaml — whichever is the cheap in-runner lane). Expect to first triage any of the 30+ orphaned tests that have rotted from never running (fix or quarantine with a reason). Then it becomes a real gate. Architect flagged this as 023-adjacent. Not blocking the RC cut (the cut doesn't gate on go test); it's a real coverage gap for the Go layer (incl. the upgrade/recovery code the 017 work lives in).
<!-- SECTION:DESCRIPTION:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Bumped to high (2026-06-13): now guards live tests — the aimed-background-download selection test (047 item A) and 039's self-heal tests (ground_truth/postswap/backup) all run only on demand until a workflow runs `go test`. Dispatch after 047 item A wraps.

ENGINEER (2026-06-13): Triage + CI gate done, awaiting foreman review before commit.

TRIAGE: ran `go test -count=1 ./...` (cache-bypassed) + `go vet ./...` against the current tree — BOTH GREEN (exit 0). All 44 cli/**/*_test.go files compile and pass; ZERO rotted, ZERO quarantined. The orphaned tests were kept alive by devs running them locally even though no CI lane ever ran them. (Ticket said ~30; actual count is 44 across cli/cmd + cli/internal.)

CI CHANGE: new dedicated workflow .github/workflows/go-test.yaml (pure Go — no Docker/DB, <1min). Triggers: push:[master] + pull_request (branches-ignore ops/**) + workflow_dispatch. Steps: checkout (fetch-depth:0, for cmd/release_verify_test.go's bare `git rev-parse HEAD`) -> setup-go (go-version-file: cli/go.mod) -> `go vet ./...` -> `go test ./...`. STRICT gate: both run with no continue-on-error / no `|| true`; non-zero fails the job and blocks the merge.

WHY A DEDICATED LANE (not fast-tests/test-hardening): fast-tests is gated behind Images on master (workflow_run) and skipped if Images fails; test-hardening only runs at RC-tag time. Both would couple the Go gate to Docker and/or run too rarely. The new lane runs in parallel with Images on master and on every non-ops PR.

FOLLOW-UP (optional, not done): could wire go-test green into the stable-release pre-flight gate (mirror release.WorkflowFastTests in cli/internal/release/workflow_check.go) so a red Go test also blocks a stable release. Left out to keep scope tight + avoid touching the release-gate code.
<!-- SECTION:NOTES:END -->
