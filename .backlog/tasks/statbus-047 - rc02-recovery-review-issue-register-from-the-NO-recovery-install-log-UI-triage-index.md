---
id: STATBUS-047
title: >-
  rc02-recovery-review: issue register from the NO recovery install log + UI
  (triage index)
status: To Do
assignee: []
created_date: '2026-06-13 08:41'
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
