---
id: STATBUS-118
title: >-
  upgrade-target-constructor: extract the approach-agnostic B-branch constructor
  (Slice 1)
status: Done
assignee:
  - '@mechanic'
created_date: '2026-06-30 20:49'
updated_date: '2026-07-03 19:40'
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
**Only Slice 1 (this task) is a clean approach-agnostic pre-A/B unit** — so the King's one-tap pre-A/B greenlight is *this task alone*. From Slice 2 onward the work is shaped by the X/Y pick:
- **Slice 2 (A/B-shaped — NOT a clean pre-A/B unit):** coherent-A pinning + trust the synthetic signer on the harness VM (fixes the multi-commit incoherence + the no-signers gate). The arc harness *already* has both (`install_statbus_at_sha` + `trust_arc_signer`, `lib/arc-helpers.sh:44/54`); the incoherence + no-signers gates are **scenario-harness-only** bugs. So under option B (scenarios merge into the arc harness) Slice 2 is *inherited*; under option A it is *added to the scenario harness*. Either way it follows the A/B pick.
- **Slice 3 (real de-risker):** migrate ONE currently-failing scenario (`3-postswap-mid-tx-kill`) off "latest commit" onto the controlled-B + the **image tail the King picks** (reuse-image if A / real-image if B) → prove GREEN on a real VM.
- **Slice 4:** migrate the remaining ~12 upgrade scenarios (mechanical, once the pilot proves the pattern).
- **Slice 5:** worker-quiesce sequencing for the post-recovery verification-install gate.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 test/install-recovery/lib/upgrade-target.sh exists, exposing construct_upgrade_target BASE_SHA SPEC → emits B_BRANCH / B_FULL / V_VERSION (+ C branch where applicable); SPEC covers the working + failing lineages
- [x] #2 .github/workflows/upgrade-arc-harness.yaml calls the library; the inline construction (the :120-177 compute + writers + build_pair + push) is removed — single source of truth, no duplicate
- [x] #3 Behavior-preserving: an upgrade-arc harness run post-refactor produces byte-identical branch structure (same V_VERSION, migration content, signing) and passes as before
- [x] #4 Signing key is parameterized (CI ephemeral vs local-generated); the post-install trust_arc_signer handshake is unchanged
- [x] #5 Local unit asserts construct_upgrade_target <base> working produces migrations/<max+1>_upgrade_arc.up.sql with the fixed upgrade_arc_fixture content + a signed commit
- [x] #6 No scenario migrated and no image-tail change in this slice (those are slices 3+, A/B-dependent)
<!-- AC:END -->

## Definition of Done
<!-- DOD:BEGIN -->
- [x] #1 The upgrade-arc harness CI run is green on the refactored construct path (the behavior-preserving proof) — landed only after that run is observed green
<!-- DOD:END -->

## Comments

<!-- COMMENTS:BEGIN -->
author: foreman
created: 2026-07-01 13:29
---
STARTED (King greenlit the upgrade-test track in parallel with recovery-core, 2026-07-01). Mechanic executes the behavior-preserving constructor extraction (upgrade-target.sh :: construct_upgrade_target, lifted from upgrade-arc-harness.yaml:120-177, workflow rewired to call it, signing-key parameterized); architect is DESIGN-OWNER + reviewer (King: 'use the architect where appropriate'); foreman reviews+commits. Behavior-preserving discipline = byte-identical branches. AC#6 out-of-scope guard holds (no scenario migrated, no image-tail change — those are A/B-dependent slices 3+). NOTE: the X/Y question is RESOLVED (King) = build-on-CI + pull (doc-020 revised); 118 itself is unchanged (approach-agnostic), and the follow-on slice 3 is now the CI-image+pull wiring. DoD unchanged: lands only after the arc-harness CI run is observed green on the refactored construct path. Engineer stays on recovery-core (disjoint files: Go vs bash).
---

author: foreman
created: 2026-07-02 06:27
---
INTERFACE RULED + mechanic implementing (2026-07-02; architect went quiet so foreman ruled with the mechanic's leans — thin shell, architect can refine). Q1=A env var ARC_SIGNING_KEY (CI sets ONCE before both calls → one arc_pubkey; local auto-gens). Q2=B push unless ARC_NO_PUSH=1 (CI real push covered by green-DoD; AC#5 local sets ARC_NO_PUSH=1). Q3=B library sets caller-scope vars ONLY (B_BRANCH/B_FULL/V_VERSION/ARC_PUBKEY), NOT $GITHUB_OUTPUT (workflow does its own) — keeps the library CI-AGNOSTIC so slice-3+ scenarios reuse it (load-bearing). Q4=A each call computes V_VERSION independently. Behavior-preserving extraction (byte-identical branches) + AC#5 local unit; mechanic reports the diff to foreman → foreman review+commit → DoD = green arc-harness CI. CONTEXT: X/Y RESOLVED (King) = BUILD-ON-CI + PULL (doc-020 revised; the image build can't be skipped, only relocated to CI; reuse-shortcut retired as lower-fidelity). So slice 3 (after 118) = migrate one scenario onto controlled-B + CI-builds-B's-image + harness-pulls (real pull-and-swap). 116 seed-incremental makes those CI image builds fast (the speed enabler).
---

author: foreman
created: 2026-07-02 06:34
---
ARCHITECT CONFIRMED all 4 interface rulings (Q1=A env-key, Q2=B ARC_NO_PUSH, Q3=B caller-scope-vars, Q4=A per-call) + 3 refinements now folded into the mechanic's build (2026-07-02): (1) Q1 — REUSE ARC_SIGNING_KEY if already set, generate+export ONLY if unset (`[ -z "$ARC_SIGNING_KEY" ] && { generate; export; }`) → first call generates, second inherits → ONE key/pubkey guaranteed by CODE not caller; export ARC_PUBKEY to caller scope. (2) Q2 — when push is SKIPPED (ARC_NO_PUSH=1), LOG LOUDLY ('B is local-only, NOT fetchable by a remote VM') so an accidental CI skip can't silently produce an unfetchable target. (3) Q3 — construct_upgrade_target MUST be a SOURCED shell function in test/install-recovery/lib/upgrade-target.sh (like arc_to in arc-helpers.sh), NOT an executed script — only a sourced function can set caller-scope vars (B_BRANCH/B_FULL/V_VERSION/ARC_PUBKEY, +V_VERSION_2). Mechanic building to these; DoD = green arc CI run. CI-agnostic so slice 3+ install-recovery scenarios consume it identically.
---

author: foreman
created: 2026-07-02 06:40
---
MECHANIC DELIVERED + FOREMAN REVIEWED FIRST-HAND (2026-07-02) — NOT committed; 2 items pending, then commit + push for the green-CI DoD. Files (uncommitted in tree): NEW test/install-recovery/lib/upgrade-target.sh (199 lines, construct_upgrade_target + _ut_write_working_v + _ut_write_failing_v); MODIFIED .github/workflows/upgrade-arc-harness.yaml (fixtures step +34/-136 — inline construction removed, now sources the library + drives it, writes the same 17 $GITHUB_OUTPUT keys). VERDICT: extraction is FAITHFUL + clean — byte-identical branch names / migration content / signing / V_VERSION vs the old inline code (verbatim-source comments cite the lifted lines), Q1 idempotent key-reuse ✓ (upgrade-target.sh:110-114 sets ARC_SIGNING_KEY in caller scope so the 2nd call inherits; ARC_PUBKEY export :121), Q3 sourced-function + caller-scope vars ✓ (:192-200), Q4 per-call deterministic V_VERSION ✓ (:128-132). AC#5 local unit (tmp/test-upgrade-target.sh) 10/10 PASS. TWO PENDING ITEMS: (1) Q2 loud-on-skip MISSING — :187-190 skips the push SILENTLY when ARC_NO_PUSH=1 (the exact silent-unfetchable-target hazard the architect flagged); routed to the mechanic to add a loud stderr log on the skip branch + re-verify AC#5. (2) --no-verify DECISION (foreman/King, held): the mechanic added --no-verify to all 4 commits; .githooks/pre-commit:110-113 scopes its --no-verify override to 'DATA-ONLY migration with NO schema impact' and says 'Do NOT use it for a schema migration' — these fixtures are CREATE TABLE (schema). Recommend the King-aligned CLEAN fix = a GUARD-LEVEL exemption (hook skips the doc/db pairing check when the ONLY staged migrations match the `_upgrade_arc`/`_upgrade_arc_2` fixture pattern) instead of call-site --no-verify (which also bypasses the tmp/, plantuml, and security-report checks). CI-IRRELEVANT either way (CI runners have no hooks) — only affects local runs, so it's a deliberate cleanup, not a blocker. NEXT (fresh foreman): land the loud-on-skip fix → decide the --no-verify vs guard-exemption → commit → push → the arc-harness CI run is the DoD oracle (and gates the 110 VM arc-run per STATBUS-071).
---

author: foreman
created: 2026-07-02 06:42
---
UPDATE (2026-07-02) — mechanic folded in all 3 architect refinements; the 1 gap I flagged is CLOSED. R1 idempotent key (library owns ssh-keygen + exports ARC_SIGNING_KEY + ARC_PUBKEY; the CI workflow step no longer keygens/exports — library is the single owner; arc_pubkey in $GITHUB_OUTPUT reads ${ARC_PUBKEY}). R2 loud-on-skip NOW PRESENT (WARNING 'push SKIPPED (ARC_NO_PUSH=1): <B>/<C> local-only, NOT fetchable by a remote VM' to stderr, confirmed visible). R3 sourced confirmed. AC#5 local unit NOW 14/14 PASS (added R1b/R1c/R1d/R2 assertions + the original 10); bash -n clean; workflow now +44/-163, upgrade-target.sh 209 lines. ONLY ONE ITEM REMAINS before commit: the --no-verify DECISION (foreman/King) — recommend the guard-level exemption (hook skips doc/db pairing when staged migrations ALL match `_upgrade_arc`/`_upgrade_arc_2`) over call-site --no-verify; the mechanic correctly LEFT --no-verify as-is pending that call. HELD state: committed-ready-but-uncommitted in the tree, all-green. NEXT (fresh foreman): make the --no-verify/guard-exemption call → commit (pathspec: .github/workflows/upgrade-arc-harness.yaml + test/install-recovery/lib/upgrade-target.sh) → push → arc-harness CI run = the DoD oracle (and gates the 110 VM arc-run per STATBUS-071).
---

author: foreman
created: 2026-07-02 15:05
---
GUARDRAIL FIX (King-directed, 2026-07-02): the --no-verify WORKAROUND IS GONE. Committed c12750b32 — .githooks/pre-commit now carries a NAMED in-guard exemption: if EVERY staged migration matches the _upgrade_arc fixture pattern (migrations/*_upgrade_arc*.{up,down}.sql), skip ONLY the doc/db pairing check; every other check (tmp/, PlantUML, security-report) still runs; real + mixed real/fixture commits stay gated; the _upgrade_archive false-match is guarded (foreman functional-tested all 4 cases GREEN). upgrade-target.sh's 3 commit sites dropped --no-verify (that edit is uncommitted, rides with the 118 commit). The hook commit itself PASSED the hook — self-proving the exemption doesn't break it. STILL HELD for the arc-harness CI green DoD. Mechanic's constructor confirmed clean (14/14, R1/R2/R3 in, loud-on-skip present). NEXT (fresh foreman): commit 118 (.github/workflows/upgrade-arc-harness.yaml + test/install-recovery/lib/upgrade-target.sh) -> push -> arc-harness CI green = DoD (and gates the 110 VM arc-run per STATBUS-071).
---

author: foreman
created: 2026-07-02 17:42
---
COMMITTED + PUSHED + DoD ORACLE IN FLIGHT (new foreman, 2026-07-02 ~17:40). Commit 0b1b07ef4 (upgrade-arc: extract the controlled-B constructor into a shared library) — exactly the 2-file pathspec (.github/workflows/upgrade-arc-harness.yaml +38/-142, test/install-recovery/lib/upgrade-target.sh 215 lines). Foreman re-reviewed the full library first-hand before committing: loud-on-skip present (:199), --no-verify gone (superseded by c12750b32 hook exemption, noted :157-160), 17 GITHUB_OUTPUT keys verified against all downstream `needs.construct.outputs.*` references (workflow :66-86, :161-164, :215, :372-379 — names match). Arc-harness dispatched: run 28609876020, scenarios="working failing" (both lineages through the refactored constructor, end-to-end construct→images→VM arcs; chosen over the all-arcs matrix — same construct-path proof, 2 VMs instead of ~14). GREEN = DoD. Also rides: first real-VM upgrade exercise of the committed 110 read-only window (not its ACs, but a live signal).
---

author: foreman
created: 2026-07-02 17:42
---
FOOTGUN FOUND + REPAIRED (foreman, 2026-07-02) — slice-3 note: construct_upgrade_target mutates REPO-LEVEL git config (user.name=statbus-upgrade-arc[bot], user.email, gpg.format=ssh, user.signingkey=/tmp/arc_signer_$$ — upgrade-target.sh:118-121), verbatim-inherited from the CI inline code where the runner is throwaway. The AC#5 local unit (tmp/test-upgrade-target.sh) restores HEAD but NOT git config → after the mechanic's local runs, this clone's commits were authored as the bot and signed with a since-stale ephemeral key ('No principal matched' in git log). Repaired: local config overrides unset (global identity restored); 4 stale /tmp/arc_signer_* pairs left behind. NOT a blocker for this slice (CI unaffected; behavior-preserving discipline kept the library verbatim). For slice 3 (scenario harnesses call this on dev machines): save/restore git config around the call, or switch to `git -c` scoped config — decide then. The rebased local commits were re-signed correctly on push.
---

author: foreman
created: 2026-07-02 18:24
---
ARC RUN 28609876020 VERDICT (mechanic diagnosis, foreman-reviewed; full analysis tmp/mechanic-arc-28609876020.md): CONSTRUCT (this task's entire surface) = GREEN + EXACT-SHAPE MATCH — branch names test/upgrade-arc-{working,failing}[-fixed]-migration-28609876020, 4 distinct signed migration commits, one shared arc_pubkey, all 4 image dispatches succeeded first attempt. The refactor is EXONERATED: acceptance criteria 1-6 are functionally proven. The DoD (whole harness run green) is blocked by an UNRELATED NEW regression: both VM arcs died on HEALTHCHECK_REST_DOWN — PostgREST admin /ready 503 (schema cache never loads) for 20+ min post-upgrade, vs ~69s in the Jun-19 green baselines. Prime suspect = STATBUS-110's read-only window (the health check polls /ready while the DB is still read-only; OFF comes only after the completed-UPDATE). Local reproduction dispatched (mechanic): restart REST under ALTER DATABASE default_transaction_read_only=on and watch /ready — evidence lands on STATBUS-110. DoD stays UNCHECKED until an arc run is green; the fix path runs through the 110 interaction, not through this task's code.
---
<!-- COMMENTS:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Constructor extracted to test/install-recovery/lib/upgrade-target.sh (sourced function, caller-scope vars, parameterized signing key with idempotent reuse, loud-on-skip push guard); workflow rewired with the inline construction removed (commit 0b1b07ef4; --no-verify workaround replaced by the named hook exemption c12750b32). Functional proof: run 28609876020 showed exact-shape branch construction (4 signed migration commits, shared arc_pubkey, all image dispatches green) — its VM legs failed only on the then-unfixed STATBUS-110 read-only/PostgREST interaction. DoD proof: arc-harness run 28679526112 (2026-07-03, on a3eb522c8 with the doc-025 fix) is GREEN end-to-end through the refactored construct path — construct, image wait, and both scenario VMs (working: A→B completed t+55s; failing: rolled_back t+79s then C completed t+58s), every health check passing on attempt 1. Local unit 14/14. Slice-3 note stands (comment 8): scoped git config when scenario harnesses call the library on dev machines.
<!-- SECTION:FINAL_SUMMARY:END -->
