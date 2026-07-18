---
id: STATBUS-036
title: >-
  roadmap: install/upgrade robustness → Norway rollout → external standalone
  (campaign overview)
status: To Do
assignee: []
created_date: '2026-06-12 07:59'
updated_date: '2026-07-18 14:35'
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
> BENEFIT: everyone — King, foreman, every agent — orients work off one true map instead of the whole board; a stale map misroutes all of them.
> STAGE: this ticket IS the roadmap (all stages).
> COMPLEXITY: architect-design; foreman applies; King ratifies.
> DEPENDS ON: nothing.

---

Campaign master plan + critical path. This ticket is the sequencing/overview; per-item detail lives in the referenced work tickets. Rewritten 2026-07-14 (architect, King-ratified); the prior Tracks A/B era text is preserved in git history — both tracks completed in full.

NORTH STAR: unattended install/upgrade. The operator's sole action is the installer; every failure self-recovers or terminates in a clean, actionable state. Norway (rune, 32 GB production data) rolls out on the stable channel; once one full RC→stable→deploy cycle is proven, external standalone opens.

WHERE WE STAND (proven, not hoped — refreshed 2026-07-14):

1. THE RECOVERY SYSTEM IS CAMPAIGN-PROVEN. The install-recovery arc campaign closed GREEN: every coverage-map cell run-proven on real VMs (071 carries the map + campaign ledger). Park-degraded, ground-truth self-heal routing, OOM, migration-ceiling double-fire, stopped-proxy recovery (143), flagless exit-20 (144), the 12h migration ceiling (095) — shipped and run-proven. The rune failure class (10,229 restarts, nobody told) is dead in code and dead in observation.

2. THE LEDGER IS INTEGRITY-PROVEN. The ledger-integrity arc shipped whole: terminal states are teardown-immune with a state-log audit (154); a new claim atomically displaces a parked row to superseded (159); terminal rows are unresurrectable (160); every terminal write rides one core connection path (163). The upgrade row's story can no longer lie.

3. THE RELEASE PIPELINE IS LIVE-PROVEN ON BOTH PROCUREMENT PATHS. rc.05 and rc.06 are cut and the fleet is green on both: Norway converged on the TAG path and dev on the EDGE/commit path, two days running. The old tag-manifest coverage worry is closed by live deployments. The release cut is the one migration bless (166); registration is git-first with commit_tags as cache (169); self-verify checks target identity (171); config generation owns PGRST_DB_SCHEMAS (the PostgREST v12→14 hard-fail, fixed at the shared writer); a delivered apply poke can no longer be silently dropped (183 — refusals are durably queryable).

4. THE OPERATOR CONTRACT HOLDS. "Run the installer" is still the sole operator action — through park, un-park, crash recovery, repair, and the broken-restore re-attempt (both classes run-proven). Norway's own rc.03 go-live was executed by the King via ./standalone.sh install, the canonical operator path. The batch-poisoning import trap (178) is fixed and shipped.

5. THE GATE MACHINERY IS TRUSTWORTHY BY CONSTRUCTION. Test runs serialize on a kernel lock; Go tests run in CI; the empirical daemon-floor oracle runs standing on every master push (182); per-scenario install-recovery stamps compose local-or-CI runs against the RC tag's commit; the migration bless lives in the release cut alone — no second records of intent anywhere in the pipeline.

WHAT STANDS BETWEEN HERE AND NORWAY-STABLE (the King's gate: all install/upgrade tickets done):
- 071 wrap-up (In Progress): un-park-to-completion arc, C-rollback resurrection leg, the two transient-backoff legs, final fabrication cleanup (interim-net successors).
- 170 phase 2 (In Progress): the deploy workflow polls ops/ci-deploy-status.sh to a terminal verdict — needs the King's sshdoers lines on the niue slots (the fleet carries the script as of rc.06), then the workflow poll + the deliberately-failing red-run proof.
- 183 live oracle: the next cut's poke-within-seconds must converge row-completed (free at the next RC/stable cut).
- 187 top-3 (silent-error catalog from the 176 burn-down): the ABORT-branch restoreDatabase error, the pre-restore compose-stop, the CI-not-ready unschedule — ruled and fixed as their own unit.
- 069 canary transport (To Do; supporting lane): niue SSH flake + runner provisioning — the King rules whether it gates.

TRACK C — THE WALK (current positions): rune/Norway is a hardcoded canary slot for `./sb release stable` (release_canary.go:43-45) — Norway go-live and the stable gate are the SAME motion. C1 RC cut ✓. C2 gate-capable RC ✓ (rc.06, carrying 164's names + 178). C3 canary deploys ✓ (dev edge + rune tag converged at rc.05 AND rc.06). C4 `./sb release stable` → v2026.07.0 → Norway live — on the King's word once the gate list clears. C5 external standalone: scoped AFTER one full RC→stable→deploy cycle proven.

PARALLEL LANES (never block the path): quality gates 176 (go-lint, burn-down in flight) + 177 (ts-any, landed) + 186 (react-hooks warnings); product 093 (Go worker port), 142 (email), 173 (pgAdmin), 174 (Norway ident display), 179 (power-group viewpoints — designed, King review); tooling 168 (done), 175 (pg_regress echo flake), 184 (done); hygiene 035 (branch cleanup, King-gated).

CRITICAL PATH: 071 remaining arcs green + 170 phase-2 wired + 187 top-3 landed → next cut (rc.07 or straight to the stable candidate; its poke live-proves 183) → fleet canary green (convergence-honest via 170) → `./sb release stable` → Norway live → scope C5.

DONE = `./sb release stable` exits green with zero SKIP_* bypasses; the stable tag upgrades unattended on rune with zero watchdog kills + zero manual intervention; a deliberately-failed upgrade on a Norway-size DB rolls back to completion under the watchdog; the next RC cycle repeats it all untouched.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Gate-capable RC cut carrying 164 half-2 (cross-version arc green first) + 178; per-scenario stamps green at its commit — DONE at rc.06 (2026-07-14)
- [ ] #2 170 landed: deploy green = box converged, proven by one real fleet deploy reading the new signal
- [x] #3 Canary deploys completed at the gate-capable RC: dev (edge) + rune-no (tag) converged rows — DONE at rc.06 (2026-07-14)
- [ ] #4 ./sb release stable exits green with zero SKIP_* bypasses → v2026.07.0 → Norway live on stable
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

## Comments

<!-- COMMENTS:BEGIN -->
author: architect
created: 2026-07-14 10:54
---
ROADMAP REWRITE part 1/2 (architect, 2026-07-14; King ratifies, foreman applies to the description). The 2026-07-06 block is consumed: Tracks A and B are DONE IN FULL — every named item closed on the board (git history preserves the old text). The description below the campaign header should be REPLACED by this text, tracks dropped. Verified premises: board snapshot 2026-07-14 (12 To Do + 3 In Progress, nothing else open); newest tag v2026.07.0-rc.05; newest STABLE tag v2026.05.5 (the 2026.06/07 series are rc-only); canary slots dev + rune hardcoded (release_canary.go:43-45).

WHERE WE STAND (proven, not hoped — refreshed 2026-07-14):

1. THE RECOVERY SYSTEM IS CAMPAIGN-PROVEN. The install-recovery arc campaign closed GREEN: every coverage-map cell run-proven on real VMs (071 carries the map + campaign ledger). Park-degraded, ground-truth self-heal routing, OOM, migration-ceiling double-fire, stopped-proxy recovery (143), flagless exit-20 (144), the 12h migration ceiling (095) — shipped and run-proven. The rune failure class (10,229 restarts, nobody told) is dead in code and dead in observation.

2. THE LEDGER IS INTEGRITY-PROVEN. The ledger-integrity arc shipped whole: terminal states are teardown-immune with a state-log audit (154); a new claim atomically displaces a parked row to superseded (159); terminal rows are unresurrectable (160); every terminal write rides one core connection path (163). The upgrade row's story can no longer lie.

3. THE RELEASE PIPELINE IS LIVE-PROVEN ON BOTH PROCUREMENT PATHS. rc.05 is cut and the fleet is green on it: Norway converged on the TAG path (row 42441 completed 2026-07-13; the annotated-tag peel and register-fetch defects were found and fixed by those very runs — 169/054) and dev converged on the EDGE/commit path. The old B5 worry — zero coverage of the tag-manifest path — is closed by live deployments, twice. The release cut is the one migration bless (166); registration is git-first with commit_tags as cache (169); self-verify checks target identity (171); config generation owns PGRST_DB_SCHEMAS (the PostgREST v12→14 hard-fail, fixed at the shared writer).

4. THE OPERATOR CONTRACT HOLDS. "Run the installer" is still the sole operator action — through park, un-park, crash recovery, and repair. Norway's own rc.03 go-live was executed by the King via ./standalone.sh install, the canonical operator path. The last known import-side operator trap in this arc (batch-poisoning by duplicate primary controllers, 178) is King-approved and in build.

5. THE GATE MACHINERY IS TRUSTWORTHY BY CONSTRUCTION. Test runs serialize on a kernel lock; Go tests run in CI; per-scenario install-recovery stamps compose local-or-CI runs against the RC tag's commit; the migration bless lives in the release cut alone — no second records of intent anywhere in the pipeline.
---

author: architect
created: 2026-07-14 10:54
---
ROADMAP REWRITE part 2/2 (architect, 2026-07-14) — the gap, the walk, and the AC replacement.

WHAT STANDS BETWEEN HERE AND NORWAY-STABLE (the honest gap — every item named, nothing hidden):
- 170 deploy-green-means-converged (In Progress; ruled, phase-1 status script built): the deploy workflow must go green only when the box CONVERGED — otherwise the fleet walk lies to whoever reads it. Two-phase rollout rides 167's pattern.
- 164 half-2 (In Progress; ruled 2026-07-14, King-ratified: slug bytes + legacy-alias floor): the King gates the NEXT RC on the right names — "better to land on the right names before we make this release". Its cross-version arc is the oracle; no RC carries the bytes before that arc is green.
- 178 duplicate-primary detector (King-approved, in build): rides the same next RC.
- 071 wrap-up (In Progress): the campaign is closed green; the ticket closes when the framework's remaining reshaping lands. Not a gate on the stable cut — named here so nothing In Progress is invisible on the map.
- 069 canary transport (To Do): niue SSH flake + runner provisioning — hardens the gate's own transport so a red means the product, never the pipe. Supporting lane, not a gate.

TRACK C — THE WALK (unchanged structure, current positions): rune/Norway is a hardcoded canary slot for `./sb release stable` (release_canary.go:43-45) — Norway go-live and the stable gate remain the SAME motion. C1 RC cut ✓ (rc.05). C2 gate-capable RC = rc.06, the first RC carrying 164's names + 178 — cut when their oracles are green. C3 canary deploys ✓ ALREADY PROVEN AT rc.05 (dev edge + rune tag path both converged 2026-07-13) — repeat mechanically at rc.06. C4 `./sb release stable` → v2026.07.0 → Norway live on stable. C5 external standalone: scoped AFTER one full RC→stable→deploy cycle proven.

PARALLEL LANES (never block the path): quality gates 176 (go-lint) + 177 (ts-any); product 093 (Go worker port — ends the Crystal overlap), 142 (email), 173 (pgAdmin), 174 (Norway ident display), 179 (power-group viewpoints — designed, King review); tooling 168 (hook identity — re-ruled, in build), 175 (pg_regress echo flake); hygiene 035 (branch cleanup, King-gated).

CRITICAL PATH: 164-half-2 bytes + arc green, 178 landed, 170 phase-2 wired → cut rc.06 → fleet canary green (dev + rune, now convergence-honest) → `./sb release stable` → Norway live → scope C5.

DONE line: UNCHANGED from the original — it is still exactly right: `./sb release stable` exits green with zero SKIP_* bypasses; the stable tag upgrades unattended on rune with zero watchdog kills + zero manual intervention; a deliberately-failed upgrade on a Norway-size DB rolls back to completion under the watchdog; the next RC cycle repeats it all untouched.

ACCEPTANCE CRITERIA REPLACEMENT (for the foreman to apply; King ratifies): old #1-#3 are CONSUMED by reality at higher versions than they were written for (gate batch landed pre-rc.04; rc.05 green fleet-wide; canary deploys proven at rc.05). Replace the list with:
1. Gate-capable RC (rc.06) cut carrying 164 half-2 (cross-version arc green first) + 178; per-scenario stamps green at its commit
2. 170 landed: deploy green = box converged, proven by one real fleet deploy reading the new signal
3. Canary deploys completed at the gate-capable RC: dev (edge) + rune-no (tag) converged rows
4. `./sb release stable` exits green with zero SKIP_* bypasses → v2026.07.0 → Norway live on stable  [carries over]
5. External-standalone gate (C5) scoped + tasked after one full RC→stable→deploy cycle proven  [carries over]

The Implementation Notes (B5-vs-034, tag-path resolution, gate-batch coupling) stay — they are decision history, all settled, and the tag-path note is now live-proven rather than merely pinned.
---

author: foreman
created: 2026-07-18 14:35
---
GATE UPDATE (2026-07-18): the King-ruled stable-cut gate STATBUS-192 (serve-proven completed write; ruling 2026-07-16, 'finish tail first') is SATISFIED — fix shipped (7f690fb22, architect byte-reviewed) and proven on real VMs (RED run 29646835552 failed exactly at the transport-real health assert on the pre-fix product; GREEN run 29647643813 passed the full serve-proven narrative incl. backstop-silence + write probe). 192 is Done. Also today: 170 AC#2 shipped (83ce5b030 — all 7 deploy workflows poll to a terminal verdict; only AC#3's deliberately-failing red-run remains) and the fabricated flagless-selfheal scenario deleted per ruling (86c626ab0). Fleet-wide note: assert_health_passes is now transport-real (Host header) — a strictness increase on a shared gate; illusorily-green scenarios may redden on the next full suite run, which is the gate working. New triage entry: STATBUS-193 (resumeNewSb can complete a parked row, pre-existing, architect-flagged).
---
<!-- COMMENTS:END -->
