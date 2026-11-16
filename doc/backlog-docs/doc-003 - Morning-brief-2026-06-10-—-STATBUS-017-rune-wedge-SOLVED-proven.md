---
id: doc-003
title: Morning brief 2026-06-10 — STATBUS-017 rune wedge SOLVED + proven
type: other
created_date: '2026-06-09 23:30'
tags:
  - install-recovery
  - summary
  - overnight
  - STATBUS-017
  - NO-rollout
---
**Autonomous overnight run, night of 2026-06-09→10. Plain-language brief for when you wake. Full ledgers: STATBUS-017 + STATBUS-008.**

## 🟢 HEADLINE — the rune wedge is FIXED and PROVEN. The NO rollout is unblocked (pending your sign-off).

The bug you asked me to solve (STATBUS-017) is done. In plain words:

- **The problem:** when StatBus upgrades itself, it applies DB changes one at a time. Each has two back-to-back steps — make the change, then write a "done" note. If the server is killed in the few-millisecond gap between them, on restart it tries to re-apply the change, hits "already exists", and a safety check that runs *before* the recovery code gives up — so the server boot-loops forever. That's the 40-hour wedge.
- **The fix:** when that safety check fails *because of a half-finished upgrade*, hand control to the recovery code (which already knew how to restore the pre-upgrade backup and mark the upgrade "rolled back"). It was just being skipped. We only changed *who gets control when the check fails* — nothing else.
- **Proven on real servers, before-and-after:**
  - BEFORE (the bug): run 27237385049 — both test cases boot-looped (the wedge).
  - AFTER (the fix): run 27241262390 — **both restore cleanly to "rolled back", zero boot-loops, a real restore** (the half-finished change is actually undone, not faked).

This is the exact failure that cost ~40 hours on a real deployment, now reproduced and fixed on real VMs.

## 📋 The one thing waiting for you
**Review the recovery-code change and confirm the direction.** It's a small, isolated diff (2 files): commit `584919285`. I went with **roll back to the pre-upgrade backup** (the recommended, tested choice). If you'd rather it *push forward and finish the upgrade* instead, say so and I'll switch — but roll-back is the safe default and what's proven. The fix is on master but **nothing is deployed** (no release was cut). I left STATBUS-017 open for you to ratify and close.

The two supporting commits: `93074ba71` (the test reproducers + docs) and `f31ce6f86` (a test-harness fix — see below).

## ✅ Breadth — 6 more test scenarios fixed; the 3 "maybe a real bug" findings were all false alarms
- The architect adversarially triaged the 3 candidate product findings from the prior run → **all 3 were test-harness bugs, zero product bugs.** STATBUS-017 remains the only real product bug.
- 6 harness scenario fixes committed + verified (concurrent-install, both preswap-kills, between-migrations-kill, rollback-kill, drifted-unit).
- A **comprehensive run of all scenarios is running now** (started ~23:28Z, ~3.5h) to give you the full green tally + confirm the recovery-code fix didn't break any previously-green scenario. I'll have the numbers by morning.

## ⚠️ One honest note (the system working as intended)
The first GREEN attempt *failed* — but not on the fix. It caught a bug in a new test-helper (a multi-line shell-quoting issue that's bitten this harness before). The recovery code was never even reached. We fixed the helper (`f31ce6f86`) and re-ran → clean pass. This is exactly why we test on real VMs.

**Follow-up I recommend filing:** that multi-line shell-quoting bug has now recurred 4×. A small named "run-this-script-on-the-VM" helper would end the whole bug class. Not urgent.

## Remaining breadth (after the comprehensive run)
Two scenarios still need work — `3-postswap-mid-tx-kill` (same "stall never fires" shape the now-fixed reproducer had — a candidate for the same deterministic-fabrication approach) and `5-install-stage-a-killed-migrate`. I'll address them from the comprehensive run's actual results and report.

**Net: 017 solved + proven; 0 other product bugs; 6 breadth fixes; the NO rollout is unblocked once you ratify the diff.**
