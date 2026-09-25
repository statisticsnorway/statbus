---
id: STATBUS-420
title: >-
  Remove the pg_regress CI workflow; keep a local command matching the GitHub
  Fast Tests run
status: To Do
assignee: []
created_date: '2026-09-25 13:20'
labels:
  - ci
dependencies: []
priority: high
ordinal: 369200
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Owner decision 2026-09-25 13:20Z: full removal of pg_regress.yaml (duplicate of Fast Tests, gates nothing, hogs the niue runner, the destructive-executor half of STATBUS-356), while keeping a locally runnable command that matches what runs on GitHub.
## Grounded scope (2026-09-25)

pg_regress.yaml runs `./dev.sh continous-integration-test` over SSH to niue's statbus_test slot. That command runs `delete-db` + `create-db` + `migrate-and-test fast` (dev.sh:1228-1316) — the SAME fast suite Fast Tests runs on the GitHub-hosted runner, with the same sha-tagged images. The fast-tests.yaml header claim that pg_regress runs the FULL suite (incl 4xx/5xx) is stale. The release gate consults only fast-tests.yaml (cli/cmd/release/release.go:176; "pg_regress" strings there are the suite's historical name). Unique coverage: only that dev.sh tooling works on niue's real host via the sshdo-allowlisted path — CI-infrastructure self-test, and the destructive-executor half of STATBUS-356.

## Removal checklist

1. Delete `.github/workflows/pg_regress.yaml`.
2. Delete `.github/actions/extract-db-logs` (used only by pg_regress.yaml).
3. Remove `WorkflowPgRegress` and its case label (cli/internal/release/workflow_check.go:27,155); workflow_check_test.go fixtures reference the string only as parser inputs.
4. Remove the now-unused allowlisted command in `ops/niue/sshdoers:42`.
5. Update docs: `doc/release-workflow-gates.md` (lines ~48), `doc/release-ladder.md`, `doc/DEVELOPMENT.md`, `doc/STRATEGY.md`, `ops/github-runner/README.md`.
6. KEEP `./dev.sh continous-integration-test` as the locally runnable equivalent of the GitHub Fast Tests run (owner requirement: run locally the same thing that runs on GitHub), but strip the remote-only assumptions: the STATBUS-162 in-band db-log channel existed only because the workflow's SSH key was pinned to one command; locally the trap can stay or be simplified. Document it as the local equivalent.

<!-- SECTION:DESCRIPTION:END -->
