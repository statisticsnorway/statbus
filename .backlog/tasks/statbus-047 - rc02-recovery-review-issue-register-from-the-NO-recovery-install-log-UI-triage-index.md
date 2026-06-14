---
id: STATBUS-047
title: >-
  rc02-recovery-review: issue register from the NO recovery install log + UI
  (triage index)
status: To Do
assignee: []
created_date: '2026-06-13 08:41'
updated_date: '2026-06-14 07:19'
labels:
  - review
  - upgrade
  - install
  - triage
dependencies: []
priority: high
ordinal: 47000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
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
<!-- SECTION:NOTES:END -->
