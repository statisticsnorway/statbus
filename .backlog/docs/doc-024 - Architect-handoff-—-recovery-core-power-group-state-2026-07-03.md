---
id: doc-024
title: Architect handoff — recovery-core + power-group state (2026-07-03)
type: other
created_date: '2026-07-03 10:58'
tags:
  - handoff
  - architect
  - recovery-core
  - power-group
  - session-state
---
# Architect handoff — recovery-core + power-group state (2026-07-03)

*For my fresh self (Fable, 125 build). POINTERS, not restatements — the referenced doc/ticket carries the detail; read it before acting. Role = `.claude/team/architect.md`; team = statbus; board = Backlog.md MCP; foreman routes, King ratifies. Two live threads: (A) recovery-core 110→109→046→111, (B) power-group 124→125.*

## 1. Recovery-core — model + where each design lives + WHY
**Model (ratified King 2026-06-27; canonical: `doc/upgrade-recovery-model.md` + `doc/upgrade-vocabulary.md` §"Recovery — when a step fails"):** recovery is autonomous except **two** human stops (`unknown`, `restore-broke`). On a step failure → classify: **intermittent→`backoff-retry`** (in-process, exhaust→roll-back); **persistent→roll-back** (0 retries); **unknown→stop**. Enabled by 110 (read-only window makes rollback data-safe) + 109 (backoff + two curated lists). STATBUS-039 ground-truth sets DIRECTION; 046 governs only how-long/how-loud before park.

- **doc-021 (STATBUS-046)** — RATIFIED. Carries the per-step walk + the **attempt-budget boundary**: counted from the **flag-write** (service.go executeUpgrade) through **completed-write + flag-removal**; pre-flight (Phase 0) + post-completion cleanup (Phase 5) are OUTSIDE; **Phase-1 exhaust rolls back** (data-safe), **Phase-3 at-target exhaust parks**. Budget=3, same-step-twice→park, columns `recovery_attempts`/`recovery_parked_at`. WHY park not loop: at-target can't roll back (039), loop-forever exhausts disk (rune's 10,229 restarts; systemd StartLimit can't bound a ~160s/cycle loop).
- **doc-022 (STATBUS-109)** — CORRECTED + BUILT + APPROVED (foreman committed). Two inherited-from-operator errors I fixed first-hand: (a) `retryBackoff` is **LIVE** (6 callers + structural test) — do NOT delete; `backoffRetry` is a NEW independent sibling; (b) connect() self-exempt is **service.go:2960/2965** (operator's :2889-2896 was stale). **db-unreachable probe uses `reconnect()` NOT `connect()`** (engineer's catch, I confirmed: reconnect = connect + re-acquire advisory lock + re-LISTEN; the old exit-restart re-took the actor mutex on the fresh process, so the in-process retry must too; probe bounds it with a 5s ctx). `classifyStepError` is **LABEL-ONLY** at postSwapFailure — forward-step `unknown→stop` is **DEFERRED** (own nod: flips the STATBUS-039 structural-test-protected at-target/unknown flow; and needs SQLSTATE, not the English-substring `persistentStepSignatures` list which over-matches e.g. "cannot"→"cannot connect"). Refinements beyond doc: `heartbeatingSleep` heartbeats WITHIN gaps (WatchdogSec safety); `runCommandToLogCtx` = caller-owned-ctx for stall-not-deadline.
- **doc-023 (STATBUS-110 REST read-only regression)** — SHIPPED as **migration 20260703104910**. Mechanism: PostgREST's `pgrst`-channel LISTENER connects with `target_session_attrs=read-write` → libpq rejects a read-only session (`session is read-only`) → /ready 503 → health check fails (a **circular deadlock**: completion needs /ready needs listener needs read-write needs completion). Fix: `ALTER ROLE authenticator SET default_transaction_read_only = off` (role-GUC outranks database-GUC), as a migration. Empirically verified (mechanic: /ready=200 + a non-exempt role still blocked). Preserves the accident-guard — REST external writes are ALREADY maintenance-503-gated; direct-PG integrators use OTHER roles; **worker NOT exempt** (correct: its writes are what rollback discards; it has no target_session_attrs so no crash-loop). Rejected: lift-before-health (defeats crash-freeze), `PGRST_DB_CHANNEL_ENABLED=false` (breaks schema-reload + STATBUS-102). Follow-on: STATBUS-054 (v14 bump) — the role-GUC is version-independent.
- 111 (recovery UX / `./sb install` re-attempts a broken restore + operator legend) — NOT started; design in `doc/upgrade-recovery-model.md` §terminals + STATBUS-111.
- NB: doc-018/doc-019 are STUBS → `doc/read-only-upgrade-window.md` + `doc/upgrade-recovery-model.md`.

## 2. The arc lane — the shared oracle
**Run 28656025811 IN FLIGHT** = the shared install-recovery VM oracle for **110 AC#1-3** (write-block / crash-freeze / rollback-data-safe) + **118 DoD** (controlled-B constructor) + **109 behavior** (in-process backoff, exhaust→rollback, unknown→stop). The run is the ONLY oracle on the upgrade system — correctness is proven by arrival, never by reasoning (memory: `run_is_the_only_oracle`). A RED → read the arc log FIRST-HAND (transcriptDir journal/agent-*.jsonl), classify which of 110/109/118 regressed, coordinate with foreman before re-designing. Do not hand-wave; the system is empirically unpredictable.

## 3. 124 lessons — do NOT relearn (all now landed/ticketed)
- **6-object ripple:** DRAFT-001's ripple list under-counted — named 3, MISSED 3 root-selectors picking root via `power_level=1`: `timeline_power_group_def`, `statistical_unit_enterprise_id`, `timeline_power_group_refresh`. Noted on DRAFT-001's record. ANY power_level-convention change must re-base ALL SIX + the stored `derived_influenced_power_level`.
- **Template staleness → STATBUS-126:** `tmp/test-template-migrations-sha` keys on migration TIMESTAMP not content → editing an EXISTING migration doesn't rebuild the template → `./dev.sh test` runs stale → false green/red. Workaround: `rm -f tmp/test-template-migrations-sha && ./dev.sh recreate-seed && ./dev.sh create-test-template`. (Also bites the seed-drift AC#6 re-run.)
- **2>&1 dump pollution:** `echo '\sv obj' | ./sb psql > f 2>&1` captures ./sb's stderr (e.g. the stale-`./sb` banner when HEAD moved past the ./sb build) INTO the dump → invalid SQL, in BOTH up+down so INVISIBLE to the down-vs-up diff. AGENTS.md now warns. Dump stdout-only; rebuild ./sb when stale.
- **doc/db + types pairing:** a definition-changing migration MUST bundle `./dev.sh generate-doc-db` + `./sb types generate` in the held package (mandatory pre-commit hook; the regen doc/db per-object diff is the reviewable surface + an independent scope check). I missed it on 124.
- **Method that caught all of it:** full-diff review (never blind-bless) + re-question when a fix "doesn't work" (test-to-know). It caught the wider ripple AND, when the fix "failed," first the stale-template artifact then the WARN-pollution bug underneath.

## 4. 125 kickoff (build-body-2: hierarchy Shape A/B)
- **DRAFT-001 is AUTHORITATIVE** (`.backlog/drafts/draft-001`). 124 landed the 0-index substrate at **commit 4a8bf7c59** (root=0 everywhere).
- Goal: `statistical_unit_hierarchy('power_group',X)`→**Shape A** (whole DAG, members across ALL member enterprises — fixes the `statistical_unit_enterprise_id` single-enterprise COLLAPSE); **Shape B** (regular unit → lean `power_group_link` at root + `power_group_membership` sub-key on each LU node, no member expansion). `primary_only boolean DEFAULT false` param. Contract + locked decisions 1-9 + naming convention all in DRAFT-001.
- **Check FIRST:** (a) `statistical_unit_enterprise_id`'s power_group branch = THE COLLAPSE to REWORK (124 only fixed its root-selector to =0; 125 replaces the logic); (b) new `power_group_hierarchy`/`power_group_membership_hierarchy`/`power_group_link` fragments compose like `enterprise_hierarchy`/`legal_unit_hierarchy`; (c) **grep EVERY object referencing power_group_membership/power_level before designing** (the 124 ripple lesson); (d) DoD = extend 118/120 to assert Shape-A/B JSON by intent + bless (mind STATBUS-126 template rebuild). Sibling tasks: STATBUS-121 (foreign UTLA member import), STATBUS-120 (multi-control test).

## 5. Consolidation (`tmp/plans/install-upgrade-consolidation.md`) — live clusters
Presented to King; **ratification pending, NO closes executed**. Live work:
- **Real product bugs to fix:** 055 (migrate-orphan gate blind spot — NO overlap with the shipped 052), 018 (seed pg_restore --clean silent fallback), 027-product-half (`--trust-github-user` no-op on scheduled-upgrade, install.go:383), 092 (racy `--recreate` NOTIFY).
- **Harness reshape** under STATBUS-071 (kill-family + fidelity): 023/027-harness/034/082/094/096/101/108 (+073 Cat D/E). Most 073-gate reds already collapsed to landed fixes (SIGKILL-quiesce, config-generate, unmask).
- **Docs sweep:** 043 core + 045/115/085.
- **Verify+close already-built:** 084 (shipped 75c0dd9d5), 112 (archiveBackup removed — grep 0 hits), 113 (backup runner + `cli/internal/dbdump/` pkg live).
- **Re-label OUT of install/upgrade:** 120/121 (import), 124/125 (power-group), 105 (email), 020/069/093/122 (tooling), 035/038 (branch-hygiene).
- **Inherited proof obligations now on STATBUS-071:** 110 AC1-3, 109 behavior, 046 per-class arcs (A/B/C/D + the held STATBUS-044 resume-died-rollback / rune-wedge scenario), plus the harness-cluster fidelity items.

## 6. Misc for fresh self
- After reset: roll-call engineer/mechanic/tester/operator via SendMessage (they retain context). **Operator mis-routes replies to `main`** — always end delegations with "Reply to architect."
- The seed-drift fix (add `ORDER BY v.derived_priority` to migration 20260218215337:839, before ON CONFLICT) was ruled: benign surrogate-key nondeterminism, FIX not normalize, GENERATED-ALWAYS memory flag N/A (it's about hash_slot computed column, not identity id). Engineer executes; incremental-seed stays DISABLED until AC#6 verify-multidelta re-runs green (on a FRESH template — STATBUS-126).
- Standing King-discipline: approve only concrete architect backlog entries; never codenames/task-IDs to the King (plain mechanics); the-run-is-the-oracle for upgrade; no manual DB writes any env; test-to-know.
