---
id: STATBUS-047
title: >-
  rc02-recovery-review: issue register from the NO recovery install log + UI
  (triage index)
status: To Do
assignee: []
created_date: '2026-06-13 08:41'
updated_date: '2026-07-13 09:05'
labels:
  - review
  - upgrade
  - install
  - triage
dependencies: []
ordinal: 47000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
> NORTH STAR: everything observed during the live Norway recovery install is triaged to zero.
> BENEFIT: the two remaining observed warts get decided instead of forgotten — F: the retention tar blocked the install command ~17 minutes on rune (real operator-facing latency on every big-DB upgrade); H: the completion write raced the service recreate and survived only via retry (a robustness hole at the most important write). G (vestigial db-seed branch) folds into the 035 branch session.
> STAGE: Stage 2 quality index. Items A–D and B1/B2 shipped (050/051/052); E was STATBUS-032.
> COMPLEXITY: architect + King walk the two items; each agreed item becomes its own build ticket (F and H are likely engineer-substantial).
> DEPENDS ON: nothing.

---

Register of issues observed during/after the NO (rune) recovery install of v2026.06.0-rc.02 on 2026-06-13. Logs: tmp/no-install.log (local), tmp/install-logs/2026.06.0-rc.02-20260613T082742Z.log (rune). UI: Software Upgrades page.

PURPOSE: triage index. We walk these one-by-one; each agreed item gets its OWN detailed execution task (root cause + fix design). Captured here so nothing is lost.

RECOVERY ITSELF SUCCEEDED — 039 takeover validated live (NRestarts=10784 → SIGKILL-class quiesce, never SIGTERM → roll-forward, no rollback); row 187 completed; rune at rc.02 (#196); site serving; May-25 backup untouched. These are quality/correctness follow-ups, not a failed recovery.

Line refs = tmp/no-install.log.

## A. Image handling
A1 (King) — Images not pre-pulled upfront; app/worker/proxy pull lazily at "Starting services" (L109-112), not before the destructive steps. Want: pull ALL images (correct profiles) right after the binary download so a later step can't fail on a missing download.
A2 (King) — The early "Pulling updated images..." (L82) is incomplete — only some (db) pull early. Hypothesis: pre-pull omits the compose profiles → near-no-op. Likely root cause of A1.
A3 (foreman, rune journal) — On each upgrade_check the daemon runs Discovery (178 tags) + "Pre-downloading images for v2026.05.1/.2/.3..." across many/old versions — wasteful + slow; probable cause of B1. Should target only the relevant candidate(s).

## B. Upgrade-check UX (King: check hangs / still offers upgrade)
B1 — UI "Checking..." appears to hang. FINDING: daemon IS running (active+enabled, PID 3657001, cleanly restarted 10:27:42 by the 039 takeover); it received NOTIFY upgrade_check and ran discovery + the heavy image pre-download (A3), so the check doesn't resolve in the expected 10-30s. Overloaded, not hung.
B2 — UI still presents "Upgrade" though rc.02 (latest prerelease) is installed. Confirm truly-offering vs spinner-not-resolved; reflect "at latest" once the check completes.

## C. Two-pass install structure
C1 (King) — Two "StatBus Installation" blocks (L38, L4056). Pass 1 heals the wedged upgrade 187 (→ v2026.05.6-rc.01 complete incl. tar+prune+cleanup, ends 10:27:36). Pass 2 records current rc.02 as #196. Decide: justify+document or unify.
C2 (King) — INVARIANT A17 violated in pass 2 (L4059): "--inside-active-upgrade set but no upgrade flag found; proceeding (install.go:190)". Pass 2 carries a stale --inside-active-upgrade after pass 1 removed the flag. Root-cause the cross-pass flag lifecycle.
C3 (King) — Confusing dual row-write logging: 187 "[completed-normal]" full dump (L390) vs #196 terse "Recorded installed version" (L4142). RESOLVED as data: both TRUE, different rows (DB confirms inprog=0; 187 healed wedge @ v2026.05.6-rc.01; 196 @ 2026.06.0-rc.02). Fix = symmetric/clear logging + document the two-row model. (Reconciles the foreman's earlier mid-install "rc.02 not in ledger" — #196 is written by pass 2, after that snapshot.)

## D. Quiesce/takeover robustness
D1 (King) — PID liveness is INFERRED, not checked. Quiesce logs "unit likely already dead" from the SIGKILL exit status (L~57) instead of reading the concrete PID (flag file) and querying `systemctl is-active` / /proc directly. Make liveness a positive check.

## E. Health-check readiness
E1 (King) — PGRST002 first health-check fail (L384), OK attempt 2. The discussed "PostgREST admin /ready on base port +6" probe (poll readiness before the RPC health check) is STATBUS-032 (in progress, not shipped). Resurface/finish; confirm the +6 admin-port design.

## F. Backup archival
F1 (foreman; King validated) — Retention tar blocks the install command ~17 min (10:10:08 site-up → 10:27:36 complete) though the .tar.gz is off the safety path (rollback restores from the rsync DIRECTORY, not the tar). Background/detach; don't delete the source dir until the tar completes; retention tolerates "pending".

## G. Stale refs
G1 (King) — db-seed branch still on origin + reported by git fetch (L34) though seed is now a Docker image (L17 "✓ image: statbus-seed"). Confirm no code references db-seed; delete the vestigial branch. Likely cosmetic.

## H. Completion-write robustness
H1 (foreman) — DB connection dropped during the completion UPDATE of 187 (L388): "Connection stale on state=completed UPDATE, reconnecting...". The service recreate cycled the upgrade's own DB connection at the completion write; reconnect-retry saved it. Understand/reorder so the completion write doesn't race the recreate.

NEXT: walk A→H one-by-one with the King; spin a detailed execution task per agreed item (root cause + fix design). Architect (Opus 4.8) does deep root-cause per item.
<!-- SECTION:DESCRIPTION:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
**Item A (image handling) — walked with the King 2026-06-13; resolution split into two moves.**

**Root cause (A2→A1, one defect):** every service in the compose project is profile-gated (app/worker/db/rest/proxy: all / all_except_app / app — none profile-less) and COMPOSE_PROFILES is set nowhere, so a bare `docker compose pull` selects zero services and pulls nothing. The two upgrade-pipeline pre-pull sites (applyPostSwap Step 8 `service.go:3914`; `pullImages` `exec.go:184`, used by executeUpgrade pre-swap AND the daemon) were both profile-less no-ops → images fell through to the later named `up -d --no-build`, with app/worker/rest/proxy pulling only at Step 11 'Starting services' AFTER the destructive migration (no-install.log L106→L109-112). Fresh-install already did it right (`--profile all pull`, install.go:1034). Full root-cause: tmp/architect-047A-image-handling.md.

**Move 1 — IMPLEMENTED (King go), committed 447c9e96d on master.** Added `--profile all` to both bare-pull sites. Pre-pull is now real (images local before the destructive step); a pull failure aborts before destruction via the existing fail-loud. Also makes the daemon's docker_images_downloaded flag truthful. build+vet green.

**Move 2 — DESIGN ONLY, awaiting King decision (couples A3 + B1).** Background pre-download (`preDownloadImages` service.go:3073) is keep-vs-rip-out. Defect: `ORDER BY discovered_at LIMIT 3` = 3 OLDEST + no re-filter vs installed version → grinds ancient v2026.05.1/.2/.3; and it runs synchronously in the discovery cycle → blocks upgrade_check (the B1 'Checking… hangs'). The existence probe (verifyArtifacts service.go:1095, `docker manifest inspect`, newest-first, sets docker_images_status='ready') is already correct — reuse it. Recommended targeted shape (logic only, NO migration): select the single newest 'ready' candidate (committed_at DESC LIMIT 1), Go-guard newer-than-installed (mirrors discover() L2827), run off the check path. Rip-out alternative needs a migration (DROP docker_images_downloaded). Recommendation: targeted/keep — pre-staging the newest candidate shortens+de-risks the destructive window, more so after move 1. Full design: tmp/architect-047A-background-download-design.md.

**Item A move 2 (aimed background pre-download) — IMPLEMENTED + pushed (commit 581043668 on master). Closes A3 + B1.**

Mid-implementation discovery (verified, surfaced + King-released): the pre-download was broken at the mechanism level, not just mis-targeted. Compose image tags are ${COMMIT_SHORT} (not ${VERSION}); `pullImages` set only VERSION, so it re-pulled the CURRENTLY-INSTALLED images under a candidate's name and stamped that candidate docker_images_downloaded=true (a false record). It never staged any non-current version's images. (Plus: the in-loop UPDATE on a single *pgx.Conn with rows open was conn-busy-prone → flag often never persisted → re-pull every cycle.)

Fix (logic-only, NO migration — King's envelope held):
- Pure `selectNewestDownloadCandidate(installed, candidates)` (service.go) — single newest CalVer release strictly newer than installed, else none; ignores non-CalVer; non-CalVer installed → none. Unit-tested directly: cli/internal/upgrade/predownload_target_test.go, 11 cases (newest-newer-than-installed; refuse <=installed; none-at-latest; stable>prereleases; ignore non-CalVer; empty; order-independence) — all PASS.
- New `pullImagesForCommitShort(commitShort)` (exec.go) sets COMMIT_SHORT (= ShortForDisplay(commit_sha), the real image tag verifyArtifacts probes) so the pull fetches the CANDIDATE's images. Replaces VERSION-only pullImages.
- preDownloadImages: newest available/scheduled + docker_images_status='ready' + not-downloaded + newer-than-installed → pull by COMMIT_SHORT → mark downloaded (now truthful). Drains rows before pull/UPDATE.
- Decouple: discover() writes 'last checked' BEFORE the pre-download (UI check resolves immediately); redundant discoverEdge pre-download call removed.
- Warm-up fix (item 5): executeUpgrade pre-swap pull now targets the upgrade's commit via pullImagesForCommitShort(ShortForDisplay(commitSHA)) — pre-stages the exact images applyPostSwap Step 8 needs + surfaces missing-image failure before any destructive step.

Verify: `go -C cli vet ./...` + `build ./...` + `test ./...` all green (exit 0), incl. the new unit test. Pushed; the per-change go-test CI gate runs on push. Minor residue: watchdog.go:89 prose still says 'pullImages' (couldn't stage under the 3-file git scope; its behavioral claim — 10-min ctx bound — remains true of the renamed fn). Design doc: tmp/architect-047A-background-download-design.md (incl. MECHANISM FINDING). ITEM A COMPLETE (move 1 = 447c9e96d, move 2 = 581043668).

TRIAGE PROGRESS (2026-06-14):
- Item A DONE — move 1 (447c9e96d, --profile all on both pre-pull sites) + move 2 (581043668, COMMIT_SHORT-aimed background pre-download + pure selectNewestDownloadCandidate with 11-case unit test + check/download decouple + warm-up now targets the upgrade's commit) + watchdog comment cleanup (ae7f8f437). All King-confirmed trade-offs are IN (single-newest pre-stage; warm-up targets target not current; decoupled background download). Closes A1 + A2 + A3 + B1. Foreman-reviewed byte-level + go test green + runs in CI now.
- Item B1 DONE (fell out of A — the 'Checking…' spin was the synchronous-download-in-check; decouple fixed it).
- Item B2 → STATBUS-050 (King 2026-06-14: FIX NOW). Latent stale-available-rows + supersede hierarchy-guard + prerelease-mislabel bug; root-cause verified live.
- REMAINING for one-by-one triage: C (two-pass install: A17 invariant + confusing dual-row logging), D (quiesce infers PID liveness instead of checking), E (PGRST002 first-fail / admin-/ready-on-+6 — ties to STATBUS-032), F (retention tar blocks the install command), G (db-seed branch vestigial), H (DB connection races the completion write).

Item B2 DONE → STATBUS-050 SHIPPED (commit 03ee879be, master, pushed). Tier-independent retire-vs-installed in discover() Go logic (selectStaleBelowInstalled + supersedeBelowInstalled), NO migration. The 3 stale rune rows self-heal on next discover() (newest tag 05.x < installed 06.0-rc.02).

The 'prerelease mislabeling' half (original cause #2) was REVERSED with evidence — NOT a bug: the 3 rune rows are genuine dual-tagged releases (rc + clean release on the SAME commit — foreman-verified via git rev-list), so 'release' is truthful; discovery already classifies -rc correctly (github.go:443 dash-parse via git, NOT the GitHub API flag — the 'two paths disagree' diagnosis was itself wrong). Relabelling would have corrupted correct data. Single real defect = the supersede peer-guard. Foreman byte-level reviewed; reversal independently verified; go test green.

The over-permissive prerelease channel (accepts ANY hyphenated CalVer tag) + two divergent classifiers (discovery any-dash vs installer -rc.-only) are a SEPARATE latent footgun → STATBUS-033, PULLED FORWARD as the next task (King 2026-06-14, 'deferral bites'); dispatched to engineer.

REMAINING one-by-one triage with the King: C (two-pass install: A17 invariant + dual-row logging), D (quiesce infers PID liveness vs checks it), E (PGRST002 first-fail / admin-/ready-on-+6 — ties to STATBUS-032), F (retention tar blocks the install command), G (db-seed branch vestigial), H (DB connection races the completion write).

Item C DIAGNOSED (architect, foreman-verified end-to-end incl. the C2 alarm-reversal) + HANDLED → STATBUS-051 (fix-all-principled). King decision 2026-06-15: FIX ALL, no half-measures, no forks routed back. Diagnosis writeup: tmp/architect-047C-two-pass-flag-lifecycle.md.

Findings: C2 = the 'INVARIANT A17 violated' line is a STRUCTURALLY-GUARANTEED FALSE POSITIVE on every upgrade (fix-A moved removeUpgradeFlag service.go:4453 BEFORE the only runInstallFixup call site 4524; the bypass signal is set ONLY by the fixup child exec.go:91/96; acquireOrBypass install.go:182-190 = flag-absent→A17). C1 = two ROWS correct-by-design (187 healed + 196 recorded); the confusion is the nested fixup child printing the SAME bare 'StatBus Installation' banner — relabel, do NOT unify. C3 = logging asymmetry only (187 rich dump vs 196 terse). Precision correction: #196 is authored by pass-1's post-recovery continuation (install.go:1947), NOT the fixup child (bypass=true authors nothing).

STATBUS-051 scope (all Go + doc, NO migration): (1) silence A17 honestly via the env-var signature, KEEP the hand-passed-flag misuse warning + fix the stale exec.go:82-83 comment; (2) RENAME the lying internal flag --inside-active-upgrade / STATBUS_INSIDE_ACTIVE_UPGRADE to a post-completion-fixup semantic (clean break, hidden/internal, no external contract); (3) self-identifying fixup banner; (4) symmetric completion logging (new 'completed-install' label) + two-row-model doc note. Assigned architect, In Progress.

REMAINING one-by-one triage: D (quiesce infers PID liveness vs checks it), E (PGRST002 first-fail / admin-/ready-on-+6 — ties to STATBUS-032), F (retention tar blocks the install command), G (db-seed branch vestigial), H (DB connection races the completion write).

Item C SHIPPED → STATBUS-051 (commit 4546cfbc4, master, pushed, full suite green). All four parts landed, no migration: (1) the structural A17 false-alarm is silenced honestly (3-way acquireOrBypass — env-signature fixup → EXPECTED, hand-passed bare flag → A17 kept/narrowed); (2) clean-break rename of the lying internal flag --inside-active-upgrade → --post-upgrade-fixup (+ env var + var) across all call sites/tests/docs/scenario, ZERO residual tokens; (3) self-identifying 'StatBus Post-Upgrade Install Fixup' banner; (4) symmetric completion logging (new 'completed-install' label) + two-row-model doc + a BONUS fix of the same stale step-ordering bug in doc/upgrade-timeline.md. Foreman byte-level reviewed (3-way logic, env-handshake setter==reader, ErrNoRows discrimination) + re-ran full suite (10 packages, 0 fail) + committed.

REMAINING one-by-one triage: D (quiesce infers PID liveness vs checks it), E (PGRST002 first-fail / admin-/ready-on-+6 — ties to STATBUS-032), F (retention tar blocks the install command), G (db-seed branch vestigial), H (DB connection races the completion write).

Item D DIAGNOSED (architect, foreman-verified end-to-end against live code) + HANDLED → STATBUS-052. Writeup: tmp/architect-047D-pid-liveness.md.

Finding: the takeover quiesce stopRestartUpgradeUnit (install_upgrade.go:296-323) INFERS liveness — '(unit likely already dead)' guess from the SIGKILL exit status (L304) + a SILENT break-on-10s-timeout MainPID poll (L306-313); never the authoritative flock. KEY: the codebase ALREADY rejected the PID approach the original brief suggested — pidAlive was REMOVED as a liveness guard (service.go:784-789, 'service survives SHA upgrades → PID stays alive → ghost flag'); the authoritative signal is the kernel flock (IsFlockHeld service.go:699), which Detect (state.go:172) + recoveryRollback (service.go:2107-2143) already use. So the brief was corrected: fix uses the flock, NOT PID/proc. Severity = log-honesty/robustness/consistency (NOT corruption — recoveryRollback's flock gate already serializes), same family as item C/051.

STATBUS-052 (all Go, NO migration): thread projDir into the quiesce; confirm death via IsFlockHeld(projDir)==false with explicit outcomes (released → 'confirmed dead, proceeding'; still-held@timeout → loud actionable log); flag PID/Holder kept as diagnostic WHO. OBSERVER on still-held (foreman decision, North-Star: narrate+proceed, single downstream flock gate decides; no second hard-abort gate). Assigned architect, In Progress.

REMAINING one-by-one triage: E (PGRST002 first-fail / admin-/ready-on-+6 — ties to STATBUS-032, in progress), F (retention tar blocks the install command), G (db-seed branch vestigial), H (DB connection races the completion write).

Item D SHIPPED → STATBUS-052 (commit 3ea22ae27, master, pushed, full suite green). The takeover quiesce now CONFIRMS the SIGKILL'd upgrade is gone via the authoritative kernel flock (confirmUpgradeDeathViaFlock → IsFlockHeld==false) instead of inferring from the kill exit status + a silent MainPID-poll timeout. Explicit outcomes (released → 'confirmed dead, proceeding'; still-held@10s → loud WARNING naming the holder); OBSERVER (proceeds; recoveryRollback's flock gate is the serializer). Pure helper + unit test with a real Flock fixture. NO migration. The original brief's PID/proc suggestion was CORRECTED to the flock (codebase already removed pidAlive as a ghost-flag guard) — foreman-verified before affirming. Foreman byte-level reviewed + re-ran full suite + committed.

REMAINING one-by-one triage: E (PGRST002 first-fail / admin-/ready-on-+6 — this IS STATBUS-032, already In Progress; handling = finish/confirm 032's +6 admin-port readiness probe, not a fresh diagnosis), F (retention tar blocks the install command), G (db-seed branch vestigial), H (DB connection races the completion write).
<!-- SECTION:NOTES:END -->

## Comments

<!-- COMMENTS:BEGIN -->
author: architect
created: 2026-07-13 09:05
---
BOARD TRIAGE (architect, 2026-07-13) — CLOSE, all three remaining items overtaken with evidence: F (the retention tar blocking the install ~17 min on rune) DISSOLVED — the forensic archiveBackup tar was DELETED outright (STATBUS-112); the persistent rsync snapshot dir is the single backup artifact, and no tar exists to block anything. H (the completion write surviving only via retry — 'a robustness hole at the most important write') ABSORBED AND GENERALIZED by STATBUS-154: the teardown-immune terminalUpdate/terminalConnDo core explicitly generalized the 047-H completion-write reconnect save to EVERY terminal write and window flip (cited by name in the 154 ruling), run-proven through the health-park arc campaign. G (vestigial db-seed branch) already folded into STATBUS-035's keep-pending walk. Items A-E/B1/B2 shipped long ago per the ticket's own header. Nothing remains; recommend closing with this as the final summary.
---
<!-- COMMENTS:END -->
