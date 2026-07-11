---
id: STATBUS-036
title: >-
  roadmap: install/upgrade robustness → Norway rollout → external standalone
  (campaign overview)
status: To Do
assignee: []
created_date: '2026-06-12 07:59'
updated_date: '2026-06-12 13:16'
labels:
  - roadmap
  - install-recovery
  - upgrade
  - release
  - norway
dependencies: []
references:
  - cli/internal/upgrade/exec.go
  - cli/internal/upgrade/service.go
  - cli/internal/upgrade/watchdog.go
  - .github/workflows/install-recovery-harness.yaml
  - cli/cmd/release_canary.go
  - doc/CLOUD.md
ordinal: 36000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
> NORTH STAR: unattended install/upgrade — the operator's sole action is the installer; Norway ships on the stable channel; then external standalone opens.
> BENEFIT: everyone — King, foreman, every agent — orients work off one true map instead of 38 tickets; a stale map misroutes all of them.
> STAGE: this ticket IS the roadmap (all stages).
> COMPLEXITY: architect-design (rewrite the "WHERE WE STAND" block — it still narrates the rc.02 era, pre-park-arc); foreman applies.
> DEPENDS ON: nothing — doable now, and highest-leverage single edit on the board.

---

Campaign master plan + critical path (architect, 2026-06-11; consolidated into this ticket from doc-007 per the 2026-06-12 King convention that plans live in tickets). This ticket is the sequencing/overview; per-item detail lives in the referenced work tickets.

NORTH STAR: unattended install/upgrade. The operator's sole action is the installer; every failure self-recovers or terminates in a clean, actionable state. Norway (rune, 32 GB production data) rolls out on the stable channel; once one full RC→stable→deploy cycle is proven, external standalone opens.

WHERE WE STAND (proven, not hoped — refreshed 2026-07-06; the previous block described the rc.01 era):
- THE RECOVERY CORE IS PROVEN, NOT JUST BUILT. The two pillars shipped and survived live fire: self-heal with ground-truth routing (039: forward when at-target, rollback only when provably behind, identity-keyed restore) and park-degraded (046: an upgrade that keeps killing the server parks after 3 process deaths — or immediately on same-step-twice/deterministic/resource failures — stays alive-idle, sirens exactly once, and only a deliberate operator action grants exactly one fresh attempt). Final proof r19 (2026-07-04): the full park→siren→un-park→completed cycle green end-to-end on a real VM, with the r17 bonus of the machinery correctly bounding an UNPLANNED genuine crash loop. The rune failure class (10,229 restarts, nobody told) is dead in code and dead in observation.
- THE COUNTING MATCHES REALITY. The campaign discovered migrations actually apply in the boot-time catch-up on every resume — the budget now counts that window (the hoist), parked rows keep their recovery flag across restarts, and the un-park truly grants a fresh attempt: each of those was found by a run, fixed, and re-proven by a run. The one deliberate exception, said plainly: a broken restore's 2-death human-stop bound is restored in code (134); its dedicated run-proof is the next oracle to build, together with the 136 abort-terminal fix that r17 showed that path still needs. The rollback path is the least-fired path of the whole campaign — its two not-yet-run-proven items are named here, not hidden.
- THE OPERATOR CONFIG PATH IS SAFE. UPGRADE_CALLBACK survives every config regeneration (the park siren is armed on real boxes — observed firing through three real regenerations), and appending a key to .env.config can no longer corrupt settings (trailing-newline guarantee at the shared writer, committed 7054e7593). The NSO operator's contract — "re-run the installer" as the only action — holds through park, un-park, and repair.
- THE GATE MACHINERY LANDED. rc.04 is cut; the comprehensive-gate campaign concluded (its reds root-caused and fixed, suite reshaping continues under 071); the harness matrix split cleared the 6h ceiling; Go tests run in CI; the four historical scenario reds are closed (027's residual is the still-open trust-flag product bug, in the buildable-now queue). A1's watchdog code shipped; its arc proof rides 071. A2 (startup-tail clearance) is done. Test runs now serialize on a kernel lock (committed 8bfd3d1f6) — concurrent-run corruption is structurally impossible.
- SEED INCREMENTAL IS LIVE (116): CI seed builds delta-migrate from the prior published seed (~16-19s vs ~60s full), every in-code safety gate observed firing including the forced full baseline at depth 5; one verification criterion remains.
- WHAT STANDS BETWEEN HERE AND NORWAY-STABLE: the real-upgrade-arc framework (071, the retire-fabrication verification vehicle) and the buildable-now queue with no open dependencies (136/137/138/027/018/095), then the standing Track C walk: gate-capable RC → canary dev + rune → `./sb release stable` → Norway live. Outside the formal gate but part of Norway confidence: the 044 battery residuals (rune-wedge scenario + systemd empirics). The board now carries NORTH STAR / BENEFIT / STAGE / COMPLEXITY / DEPENDS ON on every open ticket; sequencing lives in the dependencies field, not in priority labels (retired 2026-07-06 by King ruling).

(The rc.01-era status block this replaces is preserved in git history — TRACK notes below retain their original June-12 phrasing; read A1/A2/B1/B2/B6 as DONE per the block above.)

TRACK A — product completeness (make the safety net unkillable):
- A1 / STATBUS-031 — the rollback-restore watchdog gap. The LAST known wedge-class. restoreDatabase rsync (exec.go:695-714) runs DB-size-scaled with no heartbeat; on the startup recovery path it has zero watchdog cover → SIGABRT mid-restore → flag persists → restore-from-scratch loop. Four startup entries funnel into one chokepoint (rollback(), service.go:4649). Fix = the proven 012 pattern: always-ping ticker wrapping ALL of rollback(); 10-min rsync timeout → shared 30-min const. King-gated: ratify → RED → fix → GREEN.
- A2 — startup-tail clearance: DONE (this roadmap's sweep). Every step READY=1→first-heartbeat classified; 031 is the only uncovered DB-size-scaled member. Three LOW liveness nits (network-blackhole discover, wedged-dockerd resume probes, pruneBackups RemoveAll) — environmental/self-healing, fold one-liners into 031.
- A3 / STATBUS-018 — seed restore on a populated DB: make the Seed step skip quietly (no scary pg_restore ERROR, no silent slow full-migrations fallback) on routine re-runs. Operator-UX defect for the NSO-operator reality (re-run-the-installer must be safe). Likely clears 029.
- A4 — non-gating odds-and-ends: 014 audit-trail wrinkle (markCurrentVersionCompleted overwrites rolled_back→completed — preserve the trail), 009, 010, 023, 024.

TRACK B — a validation suite that can say GREEN to the stable gate:
- B1 / STATBUS-025 — matrix split of the harness workflow. THE structural unblock, first in line. Today one serial job (~28×13min) hits the 360-min ceiling → cancelled → never success → the gate is unsatisfiable even all-green. Split: discover → build sb once → matrix one-VM-per-scenario (max-parallel ~8) → final cleanup job. The trap: per-job reap must be scoped to the job's own VM (the global always() reap murders sibling jobs' VMs). ~60 min wall-clock.
- B2 / STATBUS-026..029 — the four reds (required for the gate, not polish). 026+028 share the restoreGitState-on-VM root (fix once); 027 is a mid-tx upgrade-row assertion alignment; 029 falls out of A3/018.
- B3 — vacuity closure (the doc-006 sweep is DONE — do not re-sweep): STATBUS-030 (C15 stall-fired confirmation) + stage_head_binary standardization + reconcile the 3 Part-D needs-check rows + the wait_for_inject_stall_ready quoting fix.
- B4 — scenario rewrites: 013 (King decided service-dispatch — rewrite; 012 is the template); 015 (King call pending — recommend confirm-the-Resuming-latch-contract); 014 (recommend redesign-to-genuinely-reach-archiveBackup).
- B5 — tag→tag procurement scenario: replaceBinaryOnDisk manifest-download (the path every real Norway upgrade takes) has ZERO scenario coverage today (every service-dispatch scenario pre-stages the binary). With real RC tags an RC(n-1)→RC(n) scenario is now possible. File now, build post-gate; it is the regression net for every future upgrade.
- B6 / STATBUS-024 — add `cd cli && go test ./...` to CI; no workflow runs the 30+ Go tests whose teeth the campaign keeps adding.
- B7 — harness quality (parallel, non-gating): 023 fixture fidelity, 016 logging-accuracy, 021 VM-script transport, 020 restrict-agent realign.
- STATBUS-032 (PostgREST /ready warmup) ships in the gate-maker batch with 031 — prevents a false health-fail from entering rollback. STATBUS-033 (channel exclusivity) rides the gate batch on its own merits.

TRACK C — rollout (the path to Norway, then outward):
Structural fact: rune/Norway is a HARDCODED canary slot for `./sb release stable` (release_canary.go:43-46). The stable preflight requires a completed upgrade row for the RC commit on rune BEFORE the stable tag can exist. So Norway go-live and the stable gate are the SAME motion.
The walk: C1 RC cut ✓ → C2 gate-capable RC = first RC after B1+B2+A1 land (rc.02+) → C3 canary deploys RC→dev + RC→rune-no (the real-scale proof of the 012/031 covers) → C4 `./sb release stable` → Norway live → C5 external standalone (after one full cycle proven + operator-UX clean + B5 net green + standalone docs hardened).

CRITICAL PATH: land B1 + B2 + A1 (+032 +033) on master → cut rc.02 → matrix GREEN (~60 min) → canary rune-no → release stable → Norway live. Parallel lanes never block it: B3, B4, B5, B6, B7, A3, A4, 017-ratification.
GATES: G1 matrix workflow green at the RC commit (←B1+B2+A1) → G2 canary completed on rune (←G1's RC deployed) → G3 stable preflight all-green → tag → Norway. External standalone opens only after G3 survives one real cycle.

DONE = `./sb release stable` exits green with zero SKIP_* bypasses; the stable tag upgrades unattended on rune with zero watchdog kills + zero manual intervention; a deliberately-failed upgrade on a Norway-size DB rolls back to completion under the watchdog; the next RC cycle repeats it all untouched.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Gate-maker batch landed on master: B1 (025 matrix split) + B2 (026-029 reds) + A1 (031) + 032 + 033
- [ ] #2 rc.02 cut carrying that batch; its tag-push matrix harness run is GREEN (~60 min) at the RC commit
- [ ] #3 Canary deploys completed: RC → dev and RC → rune-no (the Norway-scale proof of the 012/031 watchdog covers)
- [ ] #4 `./sb release stable` exits green with zero SKIP_* bypasses → Norway live on stable
- [ ] #5 External-standalone gate (C5) scoped + tasked after one full RC→stable→deploy cycle proven
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
DECISIONS/CLARIFICATIONS LOG

B5 vs 034 — procurement-path distinction (foreman-verified 2026-06-12, service.go:3605-3616). The architect FYI'd that B5 (tag→tag procurement scenario) is "superseded by 034"; verified false. The procurement dispatch branches on target shape: `if ValidateVersion(displayName)` → replaceBinaryOnDisk (TAG path — FetchManifest downloads the pre-built release-manifest binary + SHA256 verify, service.go:5040); `else` → buildBinaryOnDisk (COMMIT path — build-on-box or pre-staged skip, service.go:5119; 034 adds commit-addressed download-before-build here). 034's fail-channel targets are branch COMMITS (doc-010 killed the tag model), so 034 only ever exercises the COMMIT branch — the tag-manifest path stays at ZERO scenario coverage after 034. So B5 is COMPLEMENTARY to 034, not superseded; it stays a live, distinct call in Track B.

RESOLVED (architect-pinned 2026-06-12; double-confirmed by rune's live config): Norway's unattended production upgrade rides the TAG path. apply-latest resolves the target from the box's UPGRADE_CHANNEL (cli/cmd/upgrade.go:250-339), ignoring the pushed branch: stable/prerelease → latest matching TAG → ValidateVersion TRUE → replaceBinaryOnDisk (B5's path); edge → master commit → buildBinaryOnDisk (034's path). rune is UPGRADE_CHANNEL=prerelease (confirmed via SSH 2026-06-12) → tag path. So B5 covers the single most important untested procurement path for Norway; right slot = green before the Norway-stable cut. 034's commit-addressed download serves the OTHER (edge/commit) branch — complementary.

GATE-BATCH COUPLING — REFRAMED + GUARD SHIPPED (King correction 2026-06-12). The original "silent data loss" framing of the 031↔guard coupling was refuted by the King: a wedged box locks users out (rune accumulated zero domain writes in 18 days) — unusable installation, not data loss. The real justification was a verified code bug (pickLatestBackup restoring the LATEST, not the upgrade's OWN, backup during the aside-rename window — silent wrong-restore for any box with data). STATBUS-039 (commit 5eacd6305) SHIPPED the fix: identity-keyed restore. So the guard precondition for 031 is now MET; 031 (the rollback watchdog ticker) is no longer blocked by it and can land safely on top. The gate batch still carries 031, now decoupled from the guard (already in).

doc-007 open-questions reconciliation: Q1 (031 gates stable/Norway) SETTLED. Q4 (B5 file-now) NOT superseded — stays live. Live King calls: 015 (confirm-the-Resuming-latch-contract) + 014 (redesign-to-reach-archiveBackup) + B5 (file-now).
<!-- SECTION:NOTES:END -->
