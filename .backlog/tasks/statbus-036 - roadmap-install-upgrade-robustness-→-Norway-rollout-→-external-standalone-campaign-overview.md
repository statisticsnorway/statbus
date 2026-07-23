---
id: STATBUS-036
title: >-
  roadmap: install/upgrade robustness → Norway rollout → external standalone
  (campaign overview)
status: To Do
assignee: []
created_date: '2026-06-12 07:59'
updated_date: '2026-07-23 14:59'
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
> NORTH STAR: unattended install/upgrade. The operator runs the installer; everything else recovers on its own or stops in a clean, named state. Norway ships on the stable channel. Then external standalone opens.

THE SPINE (the whole plan in one line):
cut an RC → rune (no.statbus.org) installs it and converges → the gate list below is empty → `./sb release stable` → v2026.07.0 → Norway live on stable → scope external standalone.

Norway go-live and the stable gate are ONE motion: rune is a hardcoded canary slot of `./sb release stable` (release_canary.go:43-45).

WHAT IS PROVEN (not hoped — refreshed 2026-07-20):
- Recovery: the arc campaign closed green. Every coverage-map cell is run-proven on real VMs (071 holds the map). The rune failure class (10,229 restarts, nobody told) is dead in code and dead in observation.
- Ledger: terminal states are teardown-immune, unresurrectable, and ride one writer path (154/159/160/163). The upgrade row cannot lie.
- Release pipeline: rc.05 and rc.06 are cut; the fleet is green on both procurement paths — rune on the tag path, dev on the edge path. The release cut is the one migration bless (166).
- Serve-proof: 'completed' now means the box VERIFIABLY SERVES, at every writer including the self-heal (192 — proven RED→GREEN on real VMs, 2026-07-18). This was the King's stable-cut gate. It is satisfied.
- Operator contract: "run the installer" is still the only operator action — through park, un-park, crash recovery, repair, and the broken-restore re-attempt.
- Deploy honesty, wiring half: all 8 deploy workflows poll the box to a terminal verdict — green now means CONVERGED, not poked (170 AC#2, commit 83ce5b030).

WHAT REMAINS BEFORE THE STABLE CUT (the honest list, 2026-07-20):
- 170 red-proof: the deploy pipeline must be SEEN reporting red on a failed deploy. King-ratified today as fully automated: the arc suite asserts the status script's verdicts on real rolled-back/completed rows, and a proof arc polls a broken deploy through a production-replica sshdo transport with a per-run ephemeral key. Code is built; one commit + one harness run remain. No fleet box is ever deliberately broken.
- 187 top-3: three ruled silent-error fixes (the ABORT-branch restore error, the pre-restore compose-stop, the CI-not-ready unschedule). Ruled; the fix unit has not landed yet.
- 183 live oracle: free at the next cut — the cut's own poke must converge row-completed.
- 193 parked-row self-heal leak: ruled (guard the self-heal; small build), queued. Named here because the gate is "all install/upgrade tickets done"; the King may exclude it.
- 071 tail: DOES NOT GATE — stated plainly. The release-gating remainder is empty; every coverage-map row is proven or retired. What is left is harness quality (the churn successor, retiring the last fabrication helper).
- 069 canary (supporting lane, not a gate): the runner-health probe is provisioned on niue; a smoke-found probe bug is ruled and in fix, then re-provision + the one-push proof. It hardens the gate's own transport so a red means the product, never the pipe.

THE WALK: C1 RC cut ✓. C2 gate-capable RC ✓ (rc.06). C3 canary converged ✓ (rune tag + dev edge, at rc.05 AND rc.06). C4 `./sb release stable` → v2026.07.0 → Norway live — on the King's word once the list above is empty. C5 external standalone — scoped after one full RC→stable→deploy cycle is proven.

PARALLEL LANES (never block the path): quality gates 176 (go-lint) + 186 (react-hooks); product 093 (Go worker), 142 (email), 173 (pgAdmin), 174 (Norway ident display), 179 (power-groups — King review); tooling 175 (pg_regress echo flake); hygiene 035 (branch cleanup, King-gated).

DONE = `./sb release stable` exits green with zero SKIP_* bypasses; the stable tag upgrades unattended on rune with zero watchdog kills and zero manual intervention; a deliberately-failed upgrade on a Norway-size DB rolls back to completion under the watchdog; the next RC cycle repeats it all untouched.

Per-item detail lives in the work tickets. The 2026-07-14 rewrite and the Tracks A/B era text are preserved in git history.
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

author: foreman
created: 2026-07-23 14:59
---
KING RATIFIED (2026-07-23, in chat): the rewritten roadmap description stands as the map. Same ruling: STATBUS-193 is IN the stable-cut gate ('all install/upgrade tickets done' includes it). 193 state at ratification: built, architect-approved zero amendments, committed a8b4bdcf6; its run-proof (the postswap-health-park arc leg) is in the bundled harness dispatch currently running alongside 170's deploy-status-proof re-run. Gate list after today's closures (069 Done, 184 Done, 194 Done): 170 (one green run), 193 (same run), 187 top-3 (unstarted), 183 (free at the cut).
---
<!-- COMMENTS:END -->
