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

WHERE WE STAND (proven, not hoped):
- Two product wedges closed with RED→GREEN proof on real VMs: recovery fall-through (017) and boot-migrate watchdog cover (012, RED@78ab02598 → GREEN@7c2511087, one commit apart).
- Campaign verdict: zero confirmed product recovery bugs beyond those two across ~30 scenarios. Recovery held under every other injected fault.
- RC v2026.06.0-rc.01 cut (c616b85d0). Its tag-push harness run hits GitHub's 6h ceiling — EXPECTED; it is the live exhibit of the 025 problem, not a regression. Prerelease does not gate on the harness; only stable does.
- King decision at the cut: 031 gates the STABLE/Norway promotion (not prerelease). The wedge-fix list for that gate is bounded: 017 ✓, 012 ✓, 031 last.

TRACK A — product completeness (make the safety net unkillable):
- A1 / STATBUS-031 — the rollback-restore watchdog gap. The LAST known wedge-class. restoreDatabase rsync (exec.go:695-714) runs DB-size-scaled with no heartbeat; on the startup recovery path it has zero watchdog cover → SIGABRT mid-restore → flag persists → restore-from-scratch loop. Four startup entries funnel into one chokepoint (rollback(), service.go:4649). Fix = the proven 012 pattern: always-ping ticker wrapping ALL of rollback(); 10-min rsync timeout → shared 30-min const. King-gated: ratify → RED → fix → GREEN.
- A2 — startup-tail clearance: DONE (this roadmap's sweep). Every step READY=1→first-heartbeat classified; 031 is the only uncovered DB-size-scaled member. Three LOW liveness nits (network-blackhole discover, wedged-dockerd resume probes, pruneBackups RemoveAll) — environmental/self-healing, fold one-liners into 031.
- A3 / STATBUS-018 — seed restore on a populated DB: make the Seed step skip quietly (no scary pg_restore ERROR, no silent slow full-migrations fallback) on routine re-runs. Operator-UX defect for the African-operator reality (re-run-the-installer must be safe). Likely clears 029.
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
