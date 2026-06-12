---
id: STATBUS-034
title: >-
  fail-channel: branches-as-channels for real failure/fix upgrade arcs (King's
  design, doc-010)
status: To Do
assignee: []
created_date: '2026-06-12 05:44'
updated_date: '2026-06-12 05:55'
labels:
  - install-recovery
  - upgrade
  - channels
  - test-fidelity
  - product
  - needs-king-ratification
dependencies:
  - STATBUS-033
references:
  - .backlog/docs/doc-010
  - cli/internal/upgrade/github.go
  - cli/internal/upgrade/service.go
  - test/install-recovery/README.md
  - .github/workflows/images.yaml
priority: medium
ordinal: 34000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
THE KING'S DESIGN (2026-06-12) — full corrected direction in doc-010. CORRECTION HISTORY: the architect's first draft modeled the channel as immutable fixture tags; the King rejected it — a channel is a MUTABLE pointer (changes over time), which is exactly what a BRANCH is; tags name fixed things. The vehicle is branches-as-pointers, the repo's existing deploy primitive (ops/*/deploy/*).

THE FEATURE: test-family channels backed by branches (e.g. channel/fail = crash kind, channel/stuck = wait kind). Each branch carries prepared, signed fixture commits: base → a migration with a fixed always-latest timestamp and deliberately failing/stalling SQL → the fix-up commit. A test cycle oscillates the branch pointer between EXISTING commits (force-push base→fail→fix→base): commit SHAs stable → commit-addressed images stay built → zero CI wait per run; CI cost only when a fixture commit changes. The harness arcs nothing covers today, with zero test scaffolding in the product flow: real discovery → real procurement → real boot-migrate delta → real failure → clean terminal state → pointer moves to fix → re-upgrade → COMPLETES. Dissolves the chronic no-delta problem; first-ever coverage of the fix→retry arc; matches production reality (SSB cloud deploys ARE branch-pointer upgrades).

THE ONE ENGINEERING REQUIREMENT (verified, doc-010): commit-target procurement today is build-on-box (buildBinaryOnDisk, service.go:5059+ — "no release artifact exists for edge commits"; manifest download at :5040 is tag-addressed) and test VMs / external boxes have no Go by design. So the feature needs COMMIT-ADDRESSED BINARY DELIVERY: CI publishes the sb binary commit-addressed; commit-target procurement tries download-before-build. Bonus: lets SSB cloud deploys drop the Go-on-host dependency — cloud and standalone converge on download-procurement.

SCOPE (doc-010 §mechanics): channel→branch mapping + DiscoverCommitsViaGit generalization (hardcoded origin/master, github.go:480-485) + channel-exclusive discovery; commit-addressed artifact store + SHA256-verified download; CI triggers for fixture branches; prepared signed fixture commits + authoring runbook; 2 harness arc scenarios; supersede/retention hygiene; opt-in guard for non-test boxes; AGENTS.md + operator docs.

SEQUENCING: post-gate (does not displace B1/B2/A1, doc-007). STATBUS-033 (channel exclusivity) is related-but-independent — it rides the gate batch on its own merits. King ratifies the full design before implementation.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Full design ratified by the King: channel→branch mapping shape, commit-addressed artifact store + retention, fixture-branch baseline choice, guard shape (doc-010 open points resolved)
- [ ] #2 Commit-addressed binary procurement: CI publishes the sb binary per commit; commit-target procurement downloads (SHA256-verified) before falling back to build
- [ ] #3 Fixture branches exist with prepared signed commits (base / fail / fix per family) and built images; authoring runbook documented
- [ ] #4 Harness scenario, fail arc: install base → pointer to fail-commit → real discovery+procurement+upgrade → clean rollback/terminal + data intact → pointer to fix-commit → upgrade COMPLETES
- [ ] #5 Harness scenario, stall arc: same flow, stuck migration bounded by the watchdog/timeout covers, fix completes
- [ ] #6 Channel exclusivity: a box on a test-family branch discovers ONLY that branch; stable/prerelease boxes never see branch-commit candidates (unit + discover-level checks)
- [ ] #7 Channel + fixture workflow documented (AGENTS.md table, operator docs with do-not-use-in-production warning)
<!-- AC:END -->
