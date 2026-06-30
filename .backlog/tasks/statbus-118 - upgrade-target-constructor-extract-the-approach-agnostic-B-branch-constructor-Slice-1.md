---
id: STATBUS-118
title: >-
  upgrade-target-constructor: extract the approach-agnostic B-branch constructor
  (Slice 1)
status: To Do
assignee: []
created_date: '2026-06-30 20:49'
labels:
  - testing
  - install-recovery
  - upgrade
  - controlled-B
  - refactor
dependencies: []
references:
  - .github/workflows/upgrade-arc-harness.yaml
  - test/install-recovery/lib/arc-helpers.sh
  - test/install-recovery/lib/upgrade-target.sh
  - doc-020
  - STATBUS-071
priority: high
ordinal: 118000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
**⚠ APPROACH-AGNOSTIC (needed under both option A and option B) — does NOT depend on the X/Y test-target-strategy pick. READY TO START ON THE KING'S GO; do not start without it.**

First (foundation) slice of the controlled-B upgrade-test-target arc — see **doc-020**. Replaces the broken "upgrade-to-a-moving-HEAD" test target with a stable, pushed, known-migration target branch. This slice extracts the shared constructor only; no scenario is migrated and no image-tail is chosen here (those are slices 3+, which DO depend on the A/B pick).

## What
Lift the controlled-B branch construction that currently lives **inline** in the arc CI workflow into a standalone, callable shell library, so both the CI arc harness (now) and the install-recovery scenarios (later) build their upgrade target the same way.

**New:** `test/install-recovery/lib/upgrade-target.sh :: construct_upgrade_target BASE_SHA SPEC`
- Inputs: `BASE_SHA` (the pinned A), `SPEC` ∈ {`working`, `failing`} (the known-delta lineage).
- Emits: `B_BRANCH`, `B_FULL`, `V_VERSION` (+ the C/"fixed" branch where the lineage needs it).
- Branches off `BASE_SHA`, writes the fixed synthetic migration(s), signs the commit, pushes to origin.

## Source it lifts from (cite)
The inline construction in `.github/workflows/upgrade-arc-harness.yaml:120-177` (the `construct` job):
- `:130-136` — `latest = max(14-digit ts of A's migrations)`; `V_VERSION = latest+1`, `V_VERSION_2 = latest+2` (deterministic, A-derived).
- `:150-177` `write_working_v` — fixed `CREATE TABLE public.upgrade_arc_fixture(...) + INSERT` (+ a 2nd table `upgrade_arc_fixture_2`); **non-idempotent by design** (no `IF NOT EXISTS`).
- `:179+` `write_failing_v` — fixed `DO $$ … RAISE EXCEPTION … $$` (the deterministic V_fail).
- `build_pair` (`:199-244`) — `git checkout -B <branch> <base>` → write → `git add` → `git commit -S` → capture short/full; C amends in place (working) or replaces V_fail with the working migration (failing).
- push all branches (`:248-252`).

## Behavior-preserving — and its proof
A **pure refactor**: the extracted library must produce **byte-identical branches** (same migration number + content + signing + push) as the current inline code; the workflow is rewired to *call* the library instead of its inline copy. **Proof = the existing upgrade-arc harness run is its own oracle** — post-refactor it must produce the same branch structure and pass exactly as before. No new behavior in this slice.

## Signing-key interface note
The construct currently generates an **ephemeral signing key** in the workflow (`upgrade-arc-harness.yaml:113-118`) and signs B/C with it. `construct_upgrade_target` must **parameterize the signing key** so it is callable both ways: CI passes its ephemeral key; a local run generates one (or accepts a caller-provided key). Keep the post-install `trust_arc_signer` handshake (`lib/arc-helpers.sh:24`) unchanged.

## Verify
1. **Arc-harness equivalence (the proof):** run the upgrade-arc harness (or its construct job) → it produces the same branch structure (same `V_VERSION`, migration content, signed, pushed) and passes as before.
2. **Local unit:** call `construct_upgrade_target <test-base-sha> working` locally; assert it creates `migrations/<max+1>_upgrade_arc.up.sql` with the fixed `upgrade_arc_fixture` content and a signed commit on the expected branch name.

## Follow-on sequence (context only — NOT this task; part of the doc-020 arc / STATBUS-071)
- **Slice 2:** coherent-A pinning + trust the synthetic signer on the harness VM (fixes the multi-commit incoherence + the no-signers gate) — for a pilot.
- **Slice 3 (real de-risker):** migrate ONE currently-failing scenario (`3-postswap-mid-tx-kill`) off "latest commit" onto the controlled-B + the **image tail the King picks** (reuse-image if A / real-image if B) → prove GREEN on a real VM. **← first slice that depends on the A/B (X/Y) pick.**
- **Slice 4:** migrate the remaining ~12 upgrade scenarios (mechanical, once the pilot proves the pattern).
- **Slice 5:** worker-quiesce sequencing for the post-recovery verification-install gate.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 test/install-recovery/lib/upgrade-target.sh exists, exposing construct_upgrade_target BASE_SHA SPEC → emits B_BRANCH / B_FULL / V_VERSION (+ C branch where applicable); SPEC covers the working + failing lineages
- [ ] #2 .github/workflows/upgrade-arc-harness.yaml calls the library; the inline construction (the :120-177 compute + writers + build_pair + push) is removed — single source of truth, no duplicate
- [ ] #3 Behavior-preserving: an upgrade-arc harness run post-refactor produces byte-identical branch structure (same V_VERSION, migration content, signing) and passes as before
- [ ] #4 Signing key is parameterized (CI ephemeral vs local-generated); the post-install trust_arc_signer handshake is unchanged
- [ ] #5 Local unit asserts construct_upgrade_target <base> working produces migrations/<max+1>_upgrade_arc.up.sql with the fixed upgrade_arc_fixture content + a signed commit
- [ ] #6 No scenario migrated and no image-tail change in this slice (those are slices 3+, A/B-dependent)
<!-- AC:END -->

## Definition of Done
<!-- DOD:BEGIN -->
- [ ] #1 The upgrade-arc harness CI run is green on the refactored construct path (the behavior-preserving proof) — landed only after that run is observed green
<!-- DOD:END -->
