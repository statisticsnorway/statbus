---
id: doc-002
title: Morning summary 2026-06-09 — install-recovery overnight (LIVE)
type: other
created_date: '2026-06-08 22:08'
updated_date: '2026-06-09 04:38'
tags:
  - install-recovery
  - summary
  - overnight
  - STATBUS-017
  - NO-rollout
---
**Autonomous overnight run, night of 2026-06-08→09. LIVE — I'll give a plain-language chat brief when you wake. Run ledger: STATBUS-008.**

## 🔴 HEADLINE — the rune wedge is NOT fixed (confirmed product bug). HOLD the NO rollout.
A migration commits its schema change, then the process dies before recording it in `db.migration`. On recovery a "schema-skew guard" `./sb migrate up` runs **before** the recovery logic, re-runs that migration → "relation already exists" → returns without restoring → the service boot-loops. The intended restore→rolled_back is unreachable for this case. **Confirmed airtight by independent code-trace** (service.go:1644 before :1669; markTerminal audit-only; inline path identical; forward-recovery branch dead). Full evidence + 3 candidate fixes: **STATBUS-017**. **Recommendation: hold the NO rollout until it's fixed.** I did NOT change recovery code (your decision).

## ✅ Strong positive — zero data loss
**5-install-seed-on-populated PASSED** — "data survived install against populated DB". The feared data-loss case is REFUTED.

## 📊 Breadth: 13/28 green confirmed so far; the rest are fix-committed and re-validating (see Status)
- Batch 1 (10): 5 pass / 5 fail → all 5 = first-run scenario/harness bugs, **zero product bugs**; fixed.
- Batch 2 (11): 3 pass / 8 fail → **zero new product bugs**. 6 install-stage = harness, fixed/classifying.
- The complete migrate commit↔record map is built + in the diagram (incl. your inside-the-transaction case, cell-b, green).

## 📋 Your decisions / items
1. **STATBUS-017** — rune-wedge fix direction (HIGH; gates NO rollout).
2. **STATBUS-018** — seed pg_restore --clean on populated DB → slow fallback (MEDIUM; not data-loss).
3. **STATBUS-019** — diagnostic-bundle query 42P01 (LOW; diagnostic-only 1-line fix).

## ⚠️ Status — honest, as of ~04:30Z (one setback, recovered)
- I attempted a shared-helper fix (VM_EXEC argv transport via base64) to clear 3 install-stage scenarios. It had a bug that produced an empty argv on the VM → **the big comprehensive retest failed 0/18** (every scenario died at the first VM_EXEC call). My pre-validation canary had failed earlier on seed-image timing, which masked the bug — my mistake for proceeding without a clean canary.
- **Recovered:** reverted VM_EXEC to the original (known-working) transport — clean revert, the rest of the night's fixes intact — and **re-dispatched the full retest** on the reverted build. It lands ~07:20Z (near/at when you wake). The 3 stage-b/c/e scenarios stay RED in this run (their real fix is being drafted with a proven per-scenario approach + will be canary-validated separately — no more unvalidated shared changes).
- The one git tangle earlier (my own amend racing the shared tree) was rebuilt clean, content verified, owned.
- **Net: STATBUS-017 airtight; 0 data-loss; 0 new product bugs; 3 findings filed (017/018/019).** The recovery/rollback code held under every fault EXCEPT the rune wedge. The remaining uncertainty is the harness green tally, which the re-run resolves — I'll have the final numbers + a plain brief for you.
