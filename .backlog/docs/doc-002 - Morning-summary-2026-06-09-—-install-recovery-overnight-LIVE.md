---
id: doc-002
title: Morning summary 2026-06-09 — install-recovery overnight (LIVE)
type: other
created_date: '2026-06-08 22:08'
updated_date: '2026-06-09 01:37'
tags:
  - install-recovery
  - summary
  - overnight
  - STATBUS-017
  - NO-rollout
---
**Autonomous overnight run, night of 2026-06-08→09. LIVE — I'll give a plain-language chat brief when you wake. Run ledger: STATBUS-008.**

## 🔴 HEADLINE — the rune wedge is NOT fixed (confirmed product bug). HOLD the NO rollout.
A migration commits its schema change, then the process dies before recording it in `db.migration`. On recovery a "schema-skew guard" `./sb migrate up` runs **before** the recovery logic, re-runs that migration → "relation already exists" → returns without restoring → the service boot-loops. The intended restore→rolled_back is unreachable for this case. **Confirmed airtight by independent code-trace** (service.go:1644 before :1669; markTerminal audit-only; inline path identical; forward-recovery branch dead). Full evidence + 3 candidate fixes: **STATBUS-017**. **Recommendation: hold the NO rollout until it's fixed** — rolling out now risks repeating the wedge. I did NOT change recovery code (your decision).
(Empirical VM reproducers built + committed but hit their own harness fabrication bug on first run; architect fixing → I'll re-run to capture the wedge dump. The code proof stands regardless.)

## ✅ Strong positive — zero data loss
**5-install-seed-on-populated PASSED** — "data survived install against populated DB". The feared data-loss case is REFUTED: the product correctly protects data on a populated install (R5 classifier works).

## 📊 Breadth: 13 / 28 green (was 5)
- Batch 1 (10): 5 pass / 5 fail → all 5 failures were **first-run scenario/harness bugs, zero product bugs**; fixed (no-seed lever, install-HEAD, fabricate-row, unmask).
- Batch 2 (11): 3 pass / 8 fail → **zero new product bugs**. 2 failures were unfixed-on-old-SHA preswap kills (fixes pushed); 6 install-stage = harness (shared VM_EXEC ssh-quoting clears 3, drifted-unit, stage-d over-broad assertion) — fixed; **stage-a** is under classification (a diagnostic was added — could be a 3rd product finding if it's a cleanOrphanSessions DB-context gap).
- The complete migrate commit↔record map is now built + in the diagram: before-tx (green), **inside-tx / cell-b (green)** — your "inside the transaction" question — after-commit + migration-error (the RED wedge reproducers), after-record (green).

## 📋 Your decisions / items
1. **STATBUS-017** — rune-wedge fix direction (HIGH; gates NO rollout).
2. **STATBUS-018** — seed pg_restore --clean on populated DB → slow full-migrations fallback (MEDIUM; not data-loss; operator-facing).
3. **STATBUS-019** — diagnostic-bundle query 42P01 (LOW; diagnostic-only 1-line fix).

## Status
- Clean history pushed (the one git tangle this night — my own `git commit --amend` racing the shared tree — was rebuilt clean, content verified, owned).
- **One comprehensive retest pending** (validates all fixes GREEN + classifies stage-a + captures the wedge proof). It may land near/after you wake given the serial CI + iterative harness fixes; I'll have the final tally + plain-language brief ready.
- Confirmed product bugs: **1 critical (017), 1 medium (018), 1 low (019); 0 data-loss.** The recovery/rollback code held under every fault EXCEPT the rune wedge (017).
