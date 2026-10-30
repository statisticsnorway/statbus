---
id: STATBUS-199
title: >-
  arc-harness-stable-gate: the upgrade-arc harness is NOT a codified
  release-stable gate — runs only by board discipline
status: Done
assignee:
  - '@mechanic'
created_date: '2026-08-02 14:55'
updated_date: '2026-08-27 13:50'
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
- [x] #1 release stable gates on the upgrade-arc harness at the RC's commit, same shape as the install-recovery gate, with a loud SKIP_UPGRADE_ARCS bypass
- [x] #2 A red or missing arc run at the RC commit blocks the stable promotion with an actionable message (trigger command + watch URL)
- [ ] #3 Proven by observation: one stable-promotion attempt shown blocked (or green) by this gate on a real RC
- [x] #4 Commit-scope oracles gate at the PRERELEASE preflight (go-test, app-build-lint, test-hardening, fast-tests, test-install join the existing pg_regress + images); the stable gate no longer re-owns them and prints that it rides the RC cut's gating
- [x] #5 The arc gate is path-sensitive: an RC whose diff touches no upgrade-sensitive path rides the newest FULL-SUITE green LOUDLY (inherited tag + the path list printed); a sensitive change with no covering FULL-SUITE green blocks with the dispatch remedy
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

author: architect
created: 2026-08-16 14:18
---
D2 GAP RULING (architect, 2026-08-16; the mechanic's find is real and correctly parked — run-name evaluates once at trigger time, can reference dispatch inputs but never job outputs, so a tag-push run cannot self-label from its own decide job).

RULED: NEITHER (a) NOR (b). (a) rejected — it hangs on a run-rename capability neither the mechanic, the foreman, nor I can confirm exists; a gate design resting on an unverifiable API is not a foundation. (b) rejected as unnecessary indirection once the better shape is visible:

(c) THE GATE VERIFIES WHAT RAN, NOT WHAT THE RUN CLAIMS. The jobs list of a workflow run is ground truth the API already exposes (GET /repos/{org}/{repo}/actions/runs/{id}/jobs?per_page=100 — same auth as the runs call; the full-suite matrix names its per-arc jobs). Gate logic for the arc harness becomes: a green run at the RC commit PASSES only if its arc-job set is COMPLETE — job count/names matching the arcs present in the tree AT THAT COMMIT (git ls-tree <rcCommit> -- test/install-recovery/arcs/, local and cheap). A subset dispatch fails that completeness test by construction; a ride/skip run (decide job only, zero arc jobs) simply isn't a passing run, and the gate's EXISTING walk-back — which computes the sensitivity diff itself and never trusted any label — handles the ride correctly. Everything else in the brief stands unchanged: the walk-back, the block-with-remedy, the sensitivity file, the layer re-map.

CONSEQUENCES: (1) run-name markers become COSMETIC — keep them where they are free (the dispatch path references its inputs trivially; the mechanic is already building that) and drop the requirement everywhere else; the display_title marker-aware check in the brief is SUPERSEDED by the jobs-completeness check — strictly stronger trust (a label asserts; the job list proves). (2) One workflow, one run, no rename, no two-hop — the tag-push decide job keeps its run-full-vs-skip role unchanged. (3) The install-recovery rider (comment #1 §5) closes the same way: jobs-completeness against its scenario set — same helper, second caller. (4) Pagination note for the builder: per_page=100 covers the 31-arc matrix + decide/teardown in one page; assert no next-page rather than silently truncating.

Mechanic legwork before wiring: confirm the actual matrix job-name shape in upgrade-arc-harness.yaml (e.g. 'run-arc (working)') and pin the name-matching on it; report the shape, don't improvise a parser beyond prefix+arc-slug matching.
---

author: foreman
created: 2026-08-16 14:33
---
DURABLE STATUS for the mechanic (foreman, 2026-08-16 — message deliveries to his sessions have been lost twice; THIS TICKET is the authoritative channel): (1) 199 IS YOURS, In Progress, your frozen uncommitted diff (release.go, workflow_check.go, immutability.go, ops/release/upgrade-sensitive-paths.txt, .gitignore, install-recovery-harness.yaml) is intact and wanted — nothing landed on those files since your freeze. (2) ORDER: the STATBUS-202 AMENDMENT COMES FIRST — it blocks the King's cut. See 202 comment #2 (the AC#5 spec: git log line only under merge-base --is-ancestor, else the rebaselined-history note) and deliver as tmp/202-amendment.patch (amendment hunks ONLY vs HEAD, verified apply --check; no commit, no apply — staging is the foreman's). (3) THEN the D2 rework per comment #4 (jobs-completeness; your marker-aware display_title check is superseded — align it out, keep the free dispatch-side run-name cosmetic). (4) Your JOB-NAME LEGWORK is accepted: bare `${{ matrix.scenario }}` in both workflows, exact set-equality, no parser. (5) Your DOMAIN-DERIVATION WRINKLE (install-recovery's full-suite domain applies the HARNESS_SKIP_DEFAULT exclusion via --print-selected, today coinciding 15=15 with the naive glob by luck, not guarantee — so the completeness helper's domain step must be pluggable per caller) is ROUTED TO THE ARCHITECT — build the arcs side (pure git ls-tree glob, ruled) and PARK the scenarios-side domain derivation until his answer lands as the next comment here.
---

author: architect
created: 2026-08-16 14:34
---
SCENARIO-DOMAIN RULING (architect, 2026-08-16; written on the ticket so no session gap can lose it — answering foreman's relay of the mechanic's find, which is real: the scenarios full-suite domain is `./dev.sh test-install-recovery --print-selected` semantics including the HARNESS_SKIP_DEFAULT exclusion at run.sh:31-32, and glob==domain holds today only because 0 of 15 files carry the marker — a naive ls-tree glob would start false-blocking the day one does).

RULED: COMMIT-ACCURATE REPRODUCTION — the gate derives the scenario domain from the RC COMMIT's bytes: ls-tree the scenario files at the commit, `git show <commit>:<file>` + marker grep to apply the exclusion, no checkout, never the working tree. Rationale: the gate is a pure function of the RC commit everywhere else (run conclusions at head_sha, arc domain via ls-tree at the commit); a working-tree `--print-selected` derives from WHATEVER tree the operator happens to have — the exact drift class this gate exists to kill. Simpler is not honest here.

DUPLICATION GUARD (the cost of reproduction is a second copy of the exclusion semantics, and copies drift): a Go unit pins the gate's marker constant against the harness's own — read run.sh, assert the literal the gate greps for is byte-identical to the one run.sh applies (same source-parsing family as the 196 drift gate). If the harness marker ever changes, the pin fails loudly instead of the gate silently diverging.

CONFIRMED from his legwork: bare `${{ matrix.scenario }}` job names in both workflows → the shared comparison is exact set-equality, no parser. The pluggable split stands: domain derivation per caller (arcs = plain ls-tree glob; scenarios = ls-tree + marker exclusion), job-set comparison shared. Future note, not build scope: if arcs ever gain an exclusion mechanism, the same commit-accurate reproduction applies — the pluggable seam is where it lands.
---

author: foreman
created: 2026-08-16 14:42
---
TIME-SENSITIVE, mechanic (durable copy of the message request): CUT WINDOW PENDING — the King is ready to run the release cut, which requires a clean tracked tree. PAUSE editing tracked files at a safe point and ACK the foreman via SendMessage (include your modified-file list + rework status). Your tracked WIP rides one combined patch (export → restore-to-HEAD → King's ~5-minute cut → byte-verified re-apply; HEAD cannot move — a tag is not a commit — so restoration is deterministic). Untracked files (your sensitivity list) are invisible to the preflight and stay put. The engineer has already acked; the window opens on YOUR ack.
---

author: foreman
created: 2026-08-16 17:57
---
REVIEW RETURNED FOR COMPLETION (architect, 2026-08-16; durable copy — mechanic works from THIS comment): LOGIC APPROVED across the whole freeze — D1 re-map, jobs-completeness gate, commit-accurate scenario domain, decide job, sensitivity file with matched-files printing, first-ever-RC-treated-as-sensitive fail-safe, the .gitignore un-ignore, and the pre-approved run-name omission all read to the letter or better. RETURNED on exactly TWO MISSING UNIT ORACLES from the comment-#3 set (test-writing only, zero open design questions): (1) the completeness-check unit — workflowJobsCompleteAtCommit already has its testable apiBase seam; add the httptest-family test covering the three arms: complete, missing-jobs, and pagination-overflow (total_count > returned jobs must FAIL loudly, never truncate); (2) the walk-classification unit — diffTouchesSensitivePath: prefix matching semantics + matched-files reporting. PRIORITY: this return comes AHEAD of 203 (immediate architect turnaround promised; he line-reads the walk on the re-freeze). Add the two units, re-freeze, report to the foreman with test names + RED-first evidence where the arms allow it.
---

author: architect
created: 2026-08-16 18:08
---
FINAL REVIEW — APPROVED (architect, 2026-08-16; re-freeze with both units, line-read of checkUpgradeArcHarnessGate complete). The walk is correct end to end: green-but-incomplete falls through to the ride walk (an incomplete green is not proof, but an older full green may still cover); pending/failed/unknown block with actionable remedies; the rcTag-not-found fallback walking the whole list is logically sound (the diff comparison is endpoint-based and direction-agnostic, so even a newer anchor rides only when nothing sensitive differs); per-candidate API/resolve failures skip — they can deny a ride but never grant a pass; the domain is computed at each CANDIDATE's own commit (its suite proved its own arc set — correct, not an oversight).

ONE COMMENT NIT, recorded for the next touch (behavior fine, wording overclaims): the early-break comment asserts a sensitive change since the newest full-suite green is 'necessarily also within every OLDER candidate's (bigger) diff range' — not strictly true under reverts (a sensitive file changed after the newest anchor and later reverted to an older anchor's exact state makes the OLDER endpoint-diff clean while the newer one shows it). The BEHAVIOR is right anyway — breaking early is a conservative block, never a false green; at worst it demands a fresh full run in a rare byte-revert edge. The comment should say 'deliberately conservative' rather than 'necessarily' so nobody later relies on the false claim to 'optimize' the walk. Next-touch fix, not a re-freeze.

The two returned units landed exactly to spec (completeness: complete / missing-with-order / pagination-overflow with a genuinely non-vacuous err assertion; classifier: matched-files exactness, negative arm, and the containment-contract pin so the substring semantics cannot be silently narrowed to HasPrefix). The mechanic's own broken-fixture catch ('not-ops-related' lacking the 'ops/' substring, found by character-level RED tracing) is the discipline working. Criteria 1/2/4/5 close code-side on the foreman's commit; AC#3 and the observation arms of #4/#5 ride the next real cut and promotion, as ruled — the run remains the only oracle.
---

author: foreman
created: 2026-08-16 18:08
---
COMMITTED f97281ac2 (foreman, 2026-08-16; architect final approval in comment #9 after the walk line-read — the two returned units landed to spec, executed GREEN by the foreman: both new oracles plus the full internal/release and cmd packages). Ten files, 987 insertions / 78 deletions. Criteria 1, 2, 4, 5 CHECKED code-side: the arc harness is a codified stable gate with the loud SKIP_UPGRADE_ARCS bypass and the block-with-remedy arm; commit-scope oracles gate at the prerelease preflight (app-build-lint gated for the first time anywhere) with stable riding the cut's gating; the gate is path-sensitive with the loud RIDES line naming the inherited tag and the checked-in list. AC#3 (one real stable-promotion attempt observed through the gate) stays open — it rides the next promotion, as does the AC#4/#5 observation arms' live half (a real cut refusing-or-passing with the moved gates printed; a real RIDE on a doc-only RC). The architect's comment-wording nit (the early-break 'necessarily' overclaim — behavior correct, wording conservative-not-necessary) is recorded for the next touch of release.go, not this commit. FROM THE NEXT CUT ONWARD: the tag-push trigger fires the arc suite automatically and the manual-dispatch era ends. The mechanic's lane is now clear; 204 remains queued behind the engineer's 197.
---
<!-- COMMENTS:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Arc harness gated at stable (committed f97281ac2, 2026-08-16). AC#1–#2 code-verified; AC#3 proven by fleet observation at rc.02+ (208 comment #7). Code gates closed; observation rides the rc.10+ fleet runs.
<!-- SECTION:FINAL_SUMMARY:END -->
