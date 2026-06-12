---
id: STATBUS-034
title: >-
  fail-channel: test channel + immutable fixture tags for real failure/fix
  upgrade arcs (King's design, doc-010)
status: To Do
assignee: []
created_date: '2026-06-12 05:44'
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
  - test/install-recovery/README.md
  - .github/workflows/images.yaml
  - .github/workflows/release.yaml
priority: medium
ordinal: 34000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
THE KING'S DESIGN (2026-06-12), architect-endorsed with sharpenings — full direction in doc-010. A `test` release channel backed by a force-pushable fixture branch and IMMUTABLE versioned fixture tags (-fail.N crash / -stall.N wait; fixes ship as the next tag, replace-in-place on the same fixed far-future migration timestamp). The harness gains the two arcs nothing covers today, with ZERO test scaffolding in the product flow: real discovery → real manifest-download procurement → real boot-migrate delta → real failure → clean terminal state → fix tag → re-upgrade → COMPLETES. Subsumes the doc-007 B5 tag→tag procurement scenario; structurally dissolves the harness's chronic no-delta problem; gives the fix→retry arc (the actual operator incident experience) its first coverage ever.

SCOPE (mechanics named in doc-010 §mechanics, full design = first AC): channel filter family admission (after STATBUS-033 lands exclusivity), schedule-validator admission of fixture shapes on the test channel only, fixture tag grammar (must not collide with CalVer parsers), CI coverage (images for the fixture branch; release assets/manifests for fixture tags so procurement finds a manifest — verify images.yaml/release.yaml triggers), signed fixture commits (trusted-signers), supersede/retention hygiene (test tags never pollute real channels), 2 new harness scenarios consuming STANDING tags (CI cost paid once per fixture change, not per run), AGENTS.md + operator channel docs with do-not-use-in-production warning.

LAYERING (doc-010 §7): complements the inject layer, does not replace it — inject = surgical micro-windows (kill-in-commit↔record-window, mid-tar); fail channel = end-to-end arcs.

SEQUENCING: post-gate (does not displace B1/B2/A1 on the doc-007 critical path). DEPENDS ON STATBUS-033 (filter exclusivity must be deployed before the first fixture tag exists). King ratifies the full design before implementation.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Full design ratified by the King: tag grammar, baseline-tag choice, validator+filter admission rules, CI trigger changes, guard shape for non-harness boxes (doc-010 open points resolved)
- [ ] #2 Fixture branch + first immutable tag set exist (-fail.N, -stall.N, fix tags), signed, with images + manifests built by CI
- [ ] #3 Harness scenario: fail arc — install baseline, schedule -fail tag via real discovery+procurement, observe clean rollback/terminal state + data intact, schedule fix tag, upgrade COMPLETES
- [ ] #4 Harness scenario: stall arc — same flow, stuck migration bounded by the watchdog/timeout covers, fix tag completes
- [ ] #5 Test tags provably invisible to stable and prerelease channels (depends on STATBUS-033; asserted by unit test + a discover-level check)
- [ ] #6 Channel + fixture workflow documented (AGENTS.md table, operator docs, authoring runbook for new fixture tags)
<!-- AC:END -->
