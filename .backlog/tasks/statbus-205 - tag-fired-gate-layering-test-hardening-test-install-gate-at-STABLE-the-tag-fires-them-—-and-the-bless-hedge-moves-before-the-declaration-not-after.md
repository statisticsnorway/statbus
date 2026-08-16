---
id: STATBUS-205
title: >-
  tag-fired-gate-layering: test-hardening + test-install gate at STABLE (the tag
  fires them) — and the bless hedge moves before the declaration, not after
status: In Progress
assignee: []
created_date: '2026-08-16 19:55'
updated_date: '2026-08-16 20:07'
labels:
  - release
  - quality-gate
  - operator-ux
dependencies: []
references:
  - cli/cmd/release.go
  - cli/internal/release/immutability.go
  - .github/workflows/test-hardening.yaml
  - .github/workflows/test-install.yaml
priority: high
ordinal: 205000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
> NORTH STAR: the cut is one clean command; every gate sits at the layer whose event triggers its run; a declared decision is never second-guessed after the fact.
> FOUND: 2026-08-16, the King's live cut attempt. Both defects King-confirmed at the console; fix ordered IMMEDIATELY — he waits to cut until this lands.

FIX 1 — LAYER CORRECTION (the architect's D1 brief mislabeled two TAG-FIRED workflows as commit-scope; the King's own exception clause — "except where we need the pre-release to actually test the gate" — names them): test-hardening.yaml and test-install.yaml trigger ONLY on v*-rc.* tag push (+ dispatch) — byte-verified. Gating them at the PRE-tag preflight demands a run only the tag can start: deadlock, hit live.
- preflightChecks: REMOVE the checkPrereleaseWorkflowGate lines for WorkflowTestHardening and WorkflowTestInstall.
- releaseStableCmd: RESTORE both as stable gates (checkStableWorkflowGate, SKIP_TEST_HARDENING / SKIP_TEST_INSTALL), in the tag-scope set beside install-recovery + the arc gate.
- Fix the stable rides-line and the SKIP_* help text: the commit-scope list is images/fast-tests/go-test/app-build-lint; the two moved-back names return to the stable list.
- Comment at the preflight site naming the trigger fact and the exception clause, so nobody re-moves a tag-fired gate to the pre-tag layer again.

FIX 2 — HEDGE BEFORE, NOT AFTER: the ⚠ stable-shipped coordination warning currently prints AFTER the operator's declaration (the fixedBroken block) — second-guessing a decision already made, the mirror of the lead-with-workaround disease 202 cured. MOVE the coordination content into the REFUSAL text (one line before the declaration paragraph: "<prevTag> is a STABLE tag — this migration shipped in production; a bless must be coordinated with downstream rollouts, doc/upgrade-timeline.md"). The declared pass prints ONLY the neutral ⟳ confirmation.

ORACLES: unit — the declared pass emits no ⚠ hedge and the refusal carries the coordination line; existing 199 units asserting the two gates at preflight updated to assert them at stable; the King's clean cut is the live observation.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 prerelease preflight no longer demands tag-fired workflows; test-hardening + test-install gate at stable with their loud SKIPs; rides-line and help text truthful
- [x] #2 The stable-shipped coordination note appears in the refusal (decision time); the declared pass prints only the neutral confirmation
- [ ] #3 The King's next cut runs clean to the tag with no manual workflow triggers and no bypass flags beyond the bless declaration
<!-- AC:END -->

## Comments

<!-- COMMENTS:BEGIN -->
author: foreman
created: 2026-08-16 20:06
---
Build complete (foreman-direct; lane deviation flagged to architect — King actively waiting + mechanic session mortality; architect review still gates the commit).

**Fix 1 (layer correction)** in cli/cmd/release.go:
- preflightChecks: removed the checkPrereleaseWorkflowGate lines for WorkflowTestHardening + WorkflowTestInstall; comment renumbered 13-17→13-15 and now names the trigger fact (both workflows fire ONLY on v*-rc.* tag push + dispatch → pre-tag gating is a deadlock) + the King's exception clause verbatim.
- releaseStableCmd: both restored as stable gates via a new checkStableWorkflowGate helper (rcCommit-keyed, RC tag as dispatch ref in the Missing remedy, SKIP_TEST_HARDENING / SKIP_TEST_INSTALL loud bypasses), placed before the install-recovery + arc gates. No jobs-completeness check — fixed job set, no selector input.
- Rides-line + both Long help texts corrected: commit-scope list is now images/fast-tests/go-test/app-build-lint; the two SKIP_* moved to the stable bypass list.

**Fix 2 (hedge before, not after)**: the stable-shipped ⚠ block after the ⟳ declaration receipt is gone; the coordination line ("<prevTag> is a STABLE tag — this migration shipped in production; a bless must be coordinated with downstream rollouts, doc/upgrade-timeline.md") now prints in the REFUSAL, immediately before the declaration paragraph. Declared pass prints only the neutral ⟳ receipt. Function doc comment updated.

**Oracles** — new cli/cmd/release_gate_layer_test.go, 4 tests, all green:
- TestReleaseGateLayer_TagFiredWorkflows: two-sided pin — release.go must NOT gate the two at preflight and MUST gate them at stable, AND the workflow yamls must still be purely tag-fired (adding a branches: trigger fails the pin, forcing a deliberate re-layering).
- TestMigrationImmutability_StableCoordination_InRefusal: refusal carries the coordination line BEFORE the declaration paragraph (git fixture repo, stable predecessor).
- TestMigrationImmutability_StableCoordination_AbsentForRCPredecessor: no coordination line for an RC predecessor.
- TestMigrationImmutability_DeclaredPass_NeutralReceiptOnly: declared pass emits ⟳ and no ⚠/coordination text.

**Doc**: doc/release-workflow-gates.md still described the pre-STATBUS-199 layering (all gates at stable); table + 'Where each gate fires' bullets corrected to the 199/205 layering, with the layer rule stated up top.

gofmt clean, go vet + go build green, targeted tests 4/4; full cmd+release package test run in flight. Freezing for architect review next.
---

author: foreman
created: 2026-08-16 20:07
---
Architect APPROVED (independent verification: re-ran all four oracles himself, green; ratified the lane deviation as emergency-only, the no-completeness-arm call, and keeping the doc correction in the unit). Committed as 2438cbc0f on master (3 files, +354/−50). AC#1 and AC#2 checked — both are code-level facts now pinned by release_gate_layer_test.go. AC#3 (the King's clean cut to the tag) remains open as the live observation; the ticket closes when his cut lands. Pushing next.
---
<!-- COMMENTS:END -->
