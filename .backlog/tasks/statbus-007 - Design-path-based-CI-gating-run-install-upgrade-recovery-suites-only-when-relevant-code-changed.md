---
id: STATBUS-007
title: >-
  Design path-based CI gating: run install/upgrade/recovery suites only when
  relevant code changed
status: In Progress
assignee:
  - architect
created_date: '2026-06-07 15:15'
labels:
  - ci
  - gating
  - release
dependencies: []
references:
  - .github/workflows/
  - cli/cmd/release.go
  - doc/release-workflow-gates.md
priority: medium
ordinal: 7000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
GOAL: stop running the expensive install/upgrade/recovery test suites all the time — run/require them only when code that can actually affect them changed. Currently the gates (.github/workflows/: test-install.yaml, install-recovery-harness.yaml, test-hardening.yaml, fast-tests.yaml) trigger on prerelease tag push and the release pre-flight (cli/cmd/release.go, CheckWorkflowAtCommit) requires them regardless of what changed.

Analyze + design (read the workflows, cli/cmd/release.go, doc/release-workflow-gates.md):
1. Per gate: the code paths whose modification should REQUIRE it, with rationale. King's inputs: install + upgrade can be affected by MIGRATIONS (especially upgrade) -> migrations/ gates them; but some recovery work is really only affected by the CLI (cli/internal/upgrade|install|migrate|inject) -> the recovery gate may be NARROWER than "all cli + migrations".
2. Make the migrations->upgrade dependency AND the "recovery is cli-gated" narrower case explicit.
3. Recommend HOW to implement conditional gating: where the changed-paths check lives (release pre-flight vs workflow `paths:` filters vs a changed-files step), preserving a LOUD, RECORDED bypass — never silently skip a gate without a recorded reason (the project's strict-gating + loud-bypass principle).

This is analysis/design (a plan), NOT implementation. Hand the plan to foreman for review; implementation lands as a follow-up task.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Documented {gate -> required code paths} mapping for each install/upgrade/recovery gate, with rationale per gate
- [ ] #2 Explicit treatment of the migrations->upgrade dependency and the cli-only-gated recovery case
- [ ] #3 Recommended conditional-gating implementation approach, preserving a loud/recorded bypass (no silent skips)
- [ ] #4 Plan written to tmp/ (or a doc/ proposal) and handed to foreman for review before any implementation
<!-- AC:END -->
