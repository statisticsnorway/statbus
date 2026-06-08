---
id: doc-001
title: Overnight install-recovery validation — morning summary (2026-06-08)
type: other
created_date: '2026-06-08 10:06'
updated_date: '2026-06-08 11:05'
tags:
  - install-recovery
  - summary
  - overnight
---
**Autonomous run, night of 2026-06-07/08. LIVE SNAPSHOT — breadth still running. Full run-by-run ledger: STATBUS-008.**

## Headline
Drove the install-recovery scenarios one at a time on real Hetzner VMs (recorded on GitHub Actions). **The recovery code holds under real fault injection — 0 confirmed product recovery bugs.** Every failure resolved to a HARNESS or SCENARIO cause. The one alarm that looked like a real product bug (a "non-atomic backup") was adversarially **DISPROVEN** — archiveBackup is atomic and sound; the test's check was flaky. These scenarios had never run successfully before; running them for real shook out ~15 harness/CI bugs and surfaced a few genuine design/product items for your decision.

## ✅ Green (validated on real VMs)
1. `0-happy-install` — run 27096800159
2. `3-postswap-watchdog-reconnect` — run 27105191049 (full recovery chain: NOTIFY → executeScheduled → watchdog-timeout → reconnect → complete → cleanup)
3. `3-postswap-mid-migration-kill` — runs 27111249171 / 27111797569 (kill-during-migration → recovery)
- `archivebackup-resume`: rec-2 (NRestarts) validated; pending a 1-line harness-check fix → green
- breadth: queued; `0-happy-upgrade` hit a harness ssh-quoting bug (being fixed)

## Harness/CI fixes landed (pushed; HEAD 4f6f48f14, + 2 more in flight)
- **heredoc collapse** 2bc671ecf — VM_EXEC `printf %q`; fixed watchdog-reconnect + startup-timeout
- **NOTIFY wake** 3bb6d703d — watchdog-reconnect supervised dispatch
- **shared orphan-count assertion** 8366440d9 — `grep -c .` + pipefail double-zero; cleared 7 scenarios
- **mirror.gcr.io Images hardening** 44bb85f4e — Docker Hub transient resilience
- **migrate fix-chain** f018a75d8 → 75ceab1ff → c9f89f930 (fabricate → pre-stage+budget → checkout coherence)
- **stage-log observability** b80d725a7 — dump /tmp/stage*.log to CI (STATBUS-011)
- **archivebackup-resume** f841634a8 (kill diagnostics) + 4f6f48f14 (rec-2 bounded NRestarts) + (in flight) gzip-t check robustness
- **doc-truth** 88914920b — recovery-arc-flaw superseded note
- (in flight) **0-happy-upgrade ssh-quoting fix** — vm-bootstrap.sh:360 multi-line command collapse

## 🔔 Needs your decision (priority order)
1. **STATBUS-013 — migrate-killed-after-commit (A/B/C).** Inline `./sb install` runs a crash-recovery boot-migrate that consumes the migration delta BEFORE the resume-migrate the scenario targets → stall never fires. Recovery code WORKS; the scenario's injection model mismatches the inline path. A: switch to service-dispatch (my lean); B: fix inline env-propagation; C: accept boot-migrate as target. Reverses scenario design / touches recovery semantics → your call.
2. **STATBUS-012 — boot-migrate-up emits no WATCHDOG=1.** A large-DB boot-migrate >120s would be watchdog-killed (latent; matters for big external/standalone DBs).
3. **STATBUS-014 — archivebackup-resume A/B** (redesign to actually reach archiveBackup vs keep convergence-test) + markCurrentVersionCompleted audit-trail wrinkle.
4. **STATBUS-010 — stale CLI error message** (upgrade.go:135 mentions retired `sha-HEXHEX`).

## Resolved alarms (no action — recorded for transparency)
- **"Backup non-atomic" → FALSE POSITIVE.** archiveBackup IS atomic (exec.go:1016-1049 tar→.tmp→rename; partial-at-final impossible by construction). The `-pre.tar.gz` is forensic-only (`pickLatestBackup` skips it; restore is from a managed dir — a corrupt archive can't reach a restore). The scenario's gzip-t check misread an ssh blip as a partial → robustness fix applied. Three independent proofs in the architect's diagnosis.

## Notes
- **0 confirmed product recovery bugs** — the recovery code held under every fault injected.
- archivebackup-resume: rec-2 + gzip-t-check fix → green as a convergence test; whether it should actually exercise archiveBackup-during-stall is the STATBUS-014 A/B (your call).
- Methodology held: one scenario at a time, grind to root cause, fix harness/scenario/diagram/doc decisively, document product/design questions for you, **adversarially verify alarms** (the atomicity scare was caught and reversed) — nothing swept under the rug.
