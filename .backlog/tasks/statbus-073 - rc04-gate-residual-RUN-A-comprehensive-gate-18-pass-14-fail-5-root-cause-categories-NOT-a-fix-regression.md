---
id: STATBUS-073
title: >-
  rc04-gate-residual: RUN A comprehensive gate = 18 pass / 14 fail, 5 root-cause
  categories (NOT a fix regression)
status: To Do
assignee: []
created_date: '2026-06-17 10:13'
updated_date: '2026-06-17 10:20'
labels:
  - install-recovery
  - rc.04
  - gate
  - regression-triage
dependencies: []
priority: high
ordinal: 73000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
RUN A = the comprehensive gate run on the gating-set HEAD (73ea5210f), run 27675235157. Result: 18 PASS / 14 FAIL. Better than the prior run (27645059996, 19 fail) — the fixes moved ~5 scenarios green (legacy checkout-kill = origin/master fix worked; worker-ddl-deadlock; etc.) — but NOT a green gate. NOT a systematic regression of the carve-out/quiesce; the 14 reds are 5 distinct root causes:

CATEGORY C — REST_ADMIN_BIND_ADDRESS missing in fabricate `./sb psql` (6 scenarios, HIGHEST LEVERAGE, ONE root cause): archivebackup-resume(:250), archivebackup-watchdog(:193), resume-died-rollback(:165), mid-tx-kill(:159), watchdog-reconnect(:157), rollback-restore-watchdog(:188). Signature (exposed by the #5 psql-capture fix 11122f86f): `fabricate_scheduled_upgrade_row psql failed (rc=1): error while interpolating services.rest.ports.[]: required variable REST_ADMIN_BIND_ADDRESS is missing a value: REST_ADMIN_BIND_ADDRESS must be set in the generated .env`. The harness uploads HEAD's sb; the fabricate step runs `./sb psql` against an OLD install's .env (v2026.05.2, no REST_ADMIN_BIND_ADDRESS) while HEAD's docker-compose references it -> interpolation fails BEFORE any test logic. Likely fix: fabricate must `./sb config generate` (or equivalent) before `./sb psql`; OR a product robustness angle (psql on a config-drifted .env). Fixing this UNMASKS the 6 (some may then pass, some hit their own known-red). OWNER: operator (config/.env/docker-compose).

CATEGORY A — flag file ABSENT after the kill (4): 2-preswap-backup-kill, 2-preswap-binary-swap-kill, 2-preswap-checkout-kill, 3-postswap-container-restart-kill. Assertion `✗ expected flag file present after kill`. Recovery needs the in-progress flag to detect the interrupted upgrade; it's not present post-kill (flag not written early enough, OR the kill landed before the flag write). Product-vs-scenario TBD. OWNER: architect (recovery flag-write timing).

CATEGORY B — recovery ROLLED BACK instead of forward (2): 3-postswap-between-migrations-kill, 3-postswap-mid-migration-kill. `✗ single install exited 1 (want 0; 75 = rolled_back regression)`. These expect FORWARD recovery (state=completed); they rolled back. Real recovery behavior question (related STATBUS-046 recovery-escalation). OWNER: architect.

CATEGORY D — inject DID NOT FIRE (1): 4-rollback-kill. `✗ first install exited 0 (expected 137) — the C5 binary-swap kill did not fire`. The C5 setup kill didn't trigger. Scenario/inject issue (relates STATBUS-028). OWNER: mechanic.

CATEGORY E — VM bootstrap SSH failure (1): 5-install-stage-a-killed-migrate. `rc=2 at vm-bootstrap.sh:360: ssh ... root@$VM_IP`. Hetzner VM bootstrap SSH failed — infra, re-runnable (relates STATBUS-029). OWNER: operator (re-run; confirm transient).

PATH TO GREEN: fix C (highest leverage, 6) -> A (4) -> B (2) -> D (1); E is infra (re-run). Then re-run the comprehensive gate. WHEN-CAN-WE-CUT: after the gate is green OR its remaining reds are confirmed-known-and-acceptable. Full log: tmp/runA-failed.log (59810 lines).
<!-- SECTION:DESCRIPTION:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
PROGRESS (foreman, driving): CATEGORY C FIXED + COMMITTED 9bdba03cc — operator diagnosed (HEAD docker-compose references REST_ADMIN_BIND_ADDRESS; fabricate ran `./sb psql` against the v2026.05.2 .env that predates it); fix = `./sb config generate` before `./sb psql` in fabricate_scheduled_upgrade_row (data-helpers.sh:337). Harness-only, foreman-reviewed (clean single-line diff, fail-loud, bash -n OK). Unmasks the 6 (archivebackup-resume/-watchdog, resume-died-rollback, mid-tx-kill, watchdog-reconnect, rollback-restore-watchdog) — some will pass, some surface their own residual on the re-run.
CATEGORY E CONFIRMED INFRA (operator): stage-a-killed-migrate rc=2 at vm-bootstrap.sh:360 is a Hetzner bootstrap SSH blip (before scenario logic), not code. Re-validates automatically in the comprehensive re-run (no separate run needed).
IN FLIGHT: Category A (flag-after-kill ×4) + B (rolled-back-not-forward ×2) → architect; Category D (C5 kill didn't fire, 4-rollback-kill + binary-swap-kill) → mechanic. Commit each as it lands; push the batch → one comprehensive re-run validates all + reveals the next residual.
<!-- SECTION:NOTES:END -->
