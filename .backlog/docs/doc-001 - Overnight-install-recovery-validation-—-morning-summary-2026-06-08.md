---
id: doc-001
title: Overnight install-recovery validation — morning summary (2026-06-08)
type: other
created_date: '2026-06-08 10:06'
tags:
  - install-recovery
  - summary
  - overnight
---
**Autonomous run, night of 2026-06-07/08. LIVE SNAPSHOT — breadth scenarios still running; I'll top this up. Full run-by-run ledger: STATBUS-008.**

## Headline
Drove the install-recovery scenarios one at a time on real Hetzner VMs (recorded on GitHub Actions), as planned. **The recovery code holds under real fault injection** — every failure so far resolved to a HARNESS or SCENARIO cause, not a product recovery bug. These scenarios had never run successfully before; running them for real shook out ~13 harness/CI bugs and surfaced a few genuine product items for your decision.

## ✅ Green (validated on real VMs)
1. `0-happy-install` — run 27096800159
2. `3-postswap-watchdog-reconnect` — run 27105191049 (recovery validated end-to-end: NOTIFY → executeScheduled → watchdog-timeout → reconnect → complete → cleanup)
3. `3-postswap-mid-migration-kill` — runs 27111249171 / 27111797569 (kill-during-migration → recovery)
- breadth in progress: `0-happy-upgrade` running; ~15 more queued

## Harness/CI fixes landed (all pushed; HEAD 4f6f48f14)
- **heredoc collapse** 2bc671ecf — VM_EXEC `printf %q`; fixed watchdog-reconnect + startup-timeout
- **NOTIFY wake** 3bb6d703d — watchdog-reconnect supervised dispatch
- **shared orphan-count assertion** 8366440d9 — `grep -c .` + pipefail double-zero; cleared 7 scenarios at once
- **mirror.gcr.io Images hardening** 44bb85f4e — Docker Hub transient resilience
- **migrate fix-chain** f018a75d8 (fabricate) → 75ceab1ff (pre-stage+budget) → c9f89f930 (checkout coherence)
- **stage-log observability** b80d725a7 — dump /tmp/stage*.log to CI (STATBUS-011)
- **archivebackup-resume**: f841634a8 (kill diagnostics) + 4f6f48f14 (rec-2 bounded NRestarts assertion)
- **doc-truth** 88914920b — recovery-arc-flaw doc superseded note

## 🔔 Needs your decision (priority order)
1. **STATBUS-013 — migrate-killed-after-commit (A/B/C).** Inline `./sb install` runs a crash-recovery boot-migrate that consumes the migration delta BEFORE the resume-migrate the scenario targets → stall never fires. Recovery code WORKS; the scenario's injection model mismatches the inline path. A: switch to service-dispatch (my lean); B: fix inline env-propagation; C: accept boot-migrate as target. Reverses scenario design / touches recovery semantics → your call.
2. **Backup-atomicity (architect confirming now).** A partial/corrupt `*-pre.tar.gz` was published at the FINAL name (should be tar→.tmp→rename) after an interrupted backup. If confirmed = the **first real product bug** of the night (backup integrity). Task filed on the verdict.
3. **STATBUS-012 — boot-migrate-up emits no WATCHDOG=1.** A large-DB boot-migrate >120s would be watchdog-killed (latent; matters for big external/standalone DBs).
4. **STATBUS-014 — archivebackup-resume A/B** (redesign to actually reach archiveBackup vs keep convergence-test) + markCurrentVersionCompleted audit-trail wrinkle.
5. **STATBUS-010 — stale CLI error message** (upgrade.go:135 mentions retired `sha-HEXHEX`).

## Notes
- `migrate-killed-after-commit` = diagnosed + deferred (013), not green — needs your A/B/C.
- `archivebackup-resume`: rec-2 (NRestarts) validated; now correctly RED on the atomicity assertion (kept red — catching a real issue, not masked).
- **0 confirmed product recovery bugs**; the atomicity finding may become the first (pending architect verdict).
- Methodology held: one scenario at a time, grind to root cause, fix harness/scenario/diagram/doc decisively, document product/design questions for you — nothing swept under the rug.
