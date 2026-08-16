---
id: STATBUS-199
title: >-
  arc-harness-stable-gate: the upgrade-arc harness is NOT a codified
  release-stable gate — runs only by board discipline
status: To Do
assignee: []
created_date: '2026-08-02 14:55'
updated_date: '2026-08-02 15:35'
labels:
  - release
  - ci
  - quality-gate
  - upgrade
dependencies: []
priority: medium
ordinal: 199000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
NORTH STAR: every oracle the stable promotion depends on is codified in `./sb release stable` — zero gates that live only in team memory.

FOUND (foreman, 2026-08-02, answering the King's "is the gating codified?"): `release stable` hard-gates, at the RC's commit, on images / fast-tests / go-test / test-hardening / test-install / install-recovery-harness (cli/cmd/release.go:983-1004, each with a loud SKIP_* bypass) plus canary convergence (release_canary.go). The UPGRADE-ARC harness (.github/workflows/upgrade-arc-harness.yaml — the 31 real-dispatch arcs that carry most of the recovery-campaign proof: serve-proven writers, park lifecycle, deploy honesty) is NOT in that gate list. Its runs happen because the team's discipline fires them (071 campaign, the 08-02 pre-cut bundle) — exactly the "just in your memory" class the King asked about.

FIX SHAPE: add WorkflowUpgradeArcHarness to the stable gate chain in release.go with its own loud SKIP_UPGRADE_ARCS=1 bypass, same checkStableWorkflowGate shape as install-recovery (one line of gate + one workflow constant). Decide whether blank-selector (full arc suite) is the required shape or a named-subset run suffices — the gate checks the workflow conclusion at the RC commit, so whatever the dispatch ran must be the full honest suite for green to mean proven.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 release stable gates on the upgrade-arc harness at the RC's commit, same shape as the install-recovery gate, with a loud SKIP_UPGRADE_ARCS bypass
- [ ] #2 A red or missing arc run at the RC commit blocks the stable promotion with an actionable message (trigger command + watch URL)
- [ ] #3 Proven by observation: one stable-promotion attempt shown blocked (or green) by this gate on a real RC
- [ ] #4 Commit-scope oracles gate at the PRERELEASE preflight (go-test, app-build-lint, test-hardening, fast-tests, test-install join the existing pg_regress + images); the stable gate no longer re-owns them and prints that it rides the RC cut's gating
- [ ] #5 The arc gate is path-sensitive: an RC whose diff touches no upgrade-sensitive path rides the newest FULL-SUITE green LOUDLY (inherited tag + the path list printed); a sensitive change with no covering FULL-SUITE green blocks with the dispatch remedy
<!-- AC:END -->

## Comments

<!-- COMMENTS:BEGIN -->
author: architect
created: 2026-08-02 14:58
---
DESIGN RULING (architect, 2026-08-02; every premise byte-verified today — release.go:983-1004 gate chain, checkStableWorkflowGate at :1089, checkWorkflowAt selection in cli/internal/release/workflow_check.go, upgrade-arc-harness.yaml triggers/inputs). This completes the brief; the builder should need no design decisions.

1. FULL SUITE REQUIRED. The filed question is ruled: a green named-subset run must NOT satisfy the gate. Green at the RC commit must mean 'all arcs proven at this commit' — anything less is a green that lies, the exact class the serve-proven campaign killed at the row level. The subset selector stays (it is the iteration tool); it just cannot feed the gate.

2. CODIFY THE TRIGGER, NOT ONLY THE GATE. upgrade-arc-harness.yaml today has ONLY workflow_dispatch — so even with the gate line added, the required run would still depend on someone remembering to dispatch it: half the north star ('zero gates that live only in team memory') left standing. Add the same prerelease-tag trigger install-recovery-harness has (push: tags: v*-rc.*), running the FULL suite (blank-selector semantics). Then the honest run exists automatically at every RC cut; the gate's MISSING arm stays as the net when the trigger itself fails.

3. MAKE FULL-SUITE PROVABLE ON THE RUN RECORD. Verified: checkWorkflowAt returns green on ANY completed+success run at head_sha (first match in the API list), and the runs API exposes NO dispatch inputs — so a subset dispatch at the RC tag would satisfy a conclusion-only gate. Fix: (a) the workflow declares run-name carrying the effective selector — e.g. 'Upgrade Arc Harness — FULL SUITE' vs 'Upgrade Arc Harness — subset: working failing' (run-name sets the run's display_title, which the runs API DOES return); (b) the 199 gate check for this workflow requires the green run's display_title to carry the full-suite marker — a small variant of checkWorkflowAt that reads display_title and takes a required-marker argument (nil for the existing gates — zero behavior change for them). Alternative REJECTED for this ticket: per-arc composable stamps (the richer install-recovery stamp design) — the right long-term shape, but a bigger build than this gap needs; it can supersede the marker later without waste.

4. OTHERWISE THE FILED SHAPE: WorkflowUpgradeArcHarness constant + one checkStableWorkflowGate-family line with a loud SKIP_UPGRADE_ARCS=1 bypass; the MISSING remedy prints the dispatch command against the RC TAG (WorkflowTriggerCommand — dispatch rejects bare SHAs, the existing comment at release.go already records this).

5. RIDER, same unit (foreman sequences): the SAME any-green softness is latent in the install-recovery gate — its tag-push full run always exists, but a green subset re-dispatch at the same sha would also satisfy. The identical run-name marker + marker-aware check closes it for two lines while the builder is in both files.

6. COST, production-reality frame: full suite ≈ 31 parallel cx23 VMs ≈ €0.23 per RC cut. Nothing.

AC#3 stays the oracle — one real stable-promotion attempt observed blocked (or green) through the new gate; the run is the only oracle. Build lane: engineer (release.go + the two workflow yamls); my review on the diff.
---

author: foreman
created: 2026-08-02 15:30
---
KING RULINGS (2026-08-02, in chat) — the ticket's scope grows to match: (1) GATE LAYER CORRECTED: cheap oracles (go-test, app build & lint, test-hardening — everything that needs only the commit, not the tag) belong in the PRERELEASE preflight; the stable gate then rides on the RC's gating rather than re-owning it. Only checks that genuinely need the RC to exist (the VM harnesses at the tag's commit, canary convergence) stay at the stable layer. 'I would rather have the gating for obvious things as early as possible, except where we need the pre-release to actually test the gate.' (2) PATH-SENSITIVITY QUESTION, answered honestly: the current spec is full-suite-always (~€0.23/RC); the King asks the gate to fire only when the RC's diff against the previous RC touches directories that can influence install/upgrade (cli/, postgres/, caddy/, docker-compose*, migrations/, ops/ service files, the harness itself) — a no-relevant-changes RC then rides the previous RC's green. Design that path-filter into the gate (and state the path list IN the gate's output so a skip is loud and explains itself, never silent). Both rulings are build scope for this ticket; architect's comment #1 brief updates accordingly.
---

author: architect
created: 2026-08-02 15:35
---
BRIEF v2 (architect, 2026-08-02) — comment #1 updated for the King's two rulings (comment #2); grounding re-verified against the tree: app_build_and_lint-workflow.yaml EXISTS but has NO release constant (it gates nothing anywhere today — a bonus gap this closes); the prerelease preflight currently checks only pg_regress (release.go:189) and images (:451); stable's commit-scope re-checks sit at :983-996.

D1. LAYER RE-MAP (ruling 1 — 'gate obvious things as early as possible'):
- New constants: WorkflowAppBuildLint = "app_build_and_lint-workflow.yaml", WorkflowUpgradeArcHarness = "upgrade-arc-harness.yaml" (workflow_check.go:15-21).
- PRERELEASE preflightChecks (release.go:50) GAINS the commit-scope gates, same CheckWorkflowAtCommit + loud SKIP_* pattern as its existing pg_regress check: go-test, app-build-lint (first time gated ANYWHERE), test-hardening, fast-tests, test-install. pg_regress + images stay as-is.
- STABLE (releaseStableCmd) DROPS the commit-scope re-checks at :983-996 (images / fast-tests / go-test / test-hardening / test-install) and prints one line: 'commit-scope oracles were gated at the RC cut (prerelease preflight) — stable rides the RC's gating.' Stable KEEPS: install-recovery-harness (:1004), gains the arc gate (D2), keeps RC artifacts + canary convergence — exactly the checks that need the tag to exist.
- Consequence to state in the diff: a red master workflow now blocks at the CUT (earliest signal), not at promotion.

D2. PATH-SENSITIVE ARC GATE (ruling 2):
- ONE shared sensitivity list, a checked-in file the gate quotes: ops/release/upgrade-sensitive-paths.txt — prefixes per the King's list: cli/, postgres/, caddy/, migrations/, docker-compose (file prefix), ops/, test/install-recovery/, .github/workflows/upgrade-arc-harness.yaml, .github/workflows/images.yaml, and the list file itself (touching the list is sensitive by definition).
- WORKFLOW side (cost optimizer): tag-push trigger v*-rc.* + a first 'decide' job — git diff --name-only vs the previous RC tag against the list. Sensitive → full suite, run-name 'Upgrade Arc Harness — FULL SUITE @ <tag>'. Not sensitive → short-circuit success, run-name 'Upgrade Arc Harness — RIDES <prevRC> (no upgrade-sensitive changes)'. workflow_dispatch subset runs get run-name 'subset: <selectors>' and can never satisfy the gate.
- GATE side (correctness owner, in release.go): marker-aware check (comment #1 §3). Green FULL-SUITE at rcCommit → pass. Otherwise WALK RC tags newest-first: find the newest prior RC with a green FULL-SUITE run where git diff --name-only <candidate>..<rcCommit> touches NO listed path → RIDE, printing the inherited tag AND the path list ('no upgrade-sensitive changes since <tag>; list: …'). If a listed path changed since the newest FULL-SUITE green → BLOCK with the tag-dispatch remedy. Walk bounded (20 RCs) → loud fail forcing a fresh full run. The gate computes the diff itself (direct candidate..rc diff — no per-hop induction, correct by construction); the workflow's decide job never substitutes for it.

D3. UNCHANGED from comment #1: full-suite-required principle (§1), marker mechanism (§3, display_title via run-name), SKIP_UPGRADE_ARCS=1 loud bypass, MISSING remedy dispatches against the RC TAG, and the install-recovery marker rider (§5) — note its tag-push run must now also set a FULL-SUITE run-name.

ORACLES: AC#3 unchanged (one real promotion observed through the gate). AC#4: one real prerelease cut observed refusing on a red commit-scope workflow OR passing green with the moved gates printed. AC#5: one RIDE observed with the printed list + inherited tag (any doc-only RC gives this cheaply), and the blocking arm proven by unit on the walk logic (a live sensitive-change-without-green block is welcome but not manufactured). Go units where seams exist: the marker-aware check (httptest, family of the existing workflow_check tests) and the walk's diff classification.

Still engineer lane, post-tag; my review on the diff. Priority/cost note updated: the path filter makes the €0.23 spend per-RC conditional — exactly the King's intent.
---
<!-- COMMENTS:END -->
