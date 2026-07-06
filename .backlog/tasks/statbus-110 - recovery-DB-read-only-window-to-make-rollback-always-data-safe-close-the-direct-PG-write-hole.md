---
id: STATBUS-110
title: >-
  recovery: DB read-only window to make rollback always data-safe (close the
  direct-PG write hole)
status: In Progress
assignee:
  - '@engineer'
created_date: '2026-06-26 11:30'
updated_date: '2026-07-06 16:05'
labels:
  - upgrade
  - recovery
  - data-safety
dependencies:
  - STATBUS-071
references:
  - doc/upgrade-vocabulary.md
  - cli/internal/upgrade/service.go
  - cli/internal/upgrade/exec.go
  - STATBUS-107
  - STATBUS-039
  - STATBUS-071
  - STATBUS-109
documentation:
  - doc-018 - Read-only-upgrade-window-—-detailed-design-STATBUS-110.md
  - doc-019 - Recovery-decision-model-—-the-complete-picture.md
ordinal: 110000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
> NORTH STAR: no external write can slip into the destructive upgrade window, so rollback is always data-safe and recovery never has to stop for a human.
> BENEFIT: closes the one remaining data-loss path in rollback (a direct-PG write landing mid-window and being silently erased by a restore) — the fact that made recovery conservative; with it proven, recovery stays autonomous. AC#1 proven; remaining gain = the crash-persistence proof + the formal 039 supersession so future readers inherit the right invariant.
> STAGE: Stage 1.
> COMPLEXITY: mixed — engineer: crash-mid-window arc (AC#2); architect: 039-supersession doc + decision-tree update (AC#3); mechanic-simple: the cost paragraph (AC#4).
> DEPENDS ON: STATBUS-071 (AC#2's arc vehicle).

---

## Why
Surfaced reopening the "never restore on a guess" invariant (STATBUS-107 walkthrough, King 2026-06-26). During an upgrade's destructive+uncertain window the DIRECT Postgres path (Caddy Layer4 TCP) is UNGATED — maintenance mode is HTTP-only. A client with DB creds (a direct-PG integrator) can write during the window, and those writes are LOST on a rollback-restore. That data-loss risk is WHY recovery must never restore-on-a-guess (STATBUS-039) and instead holds for a human under uncertainty.

## Grounded facts (operator + team-lead verified; tmp/operator-upgrade-write-gating.md)
- Topology: external clients reach PG via Caddy Layer4 on PUBLIC ports; the upgrade service connects via Caddy Layer4 on the LOOPBACK bind (CADDY_DB_BIND_ADDRESS/PORT, sslmode=disable), service.go connect ~2746-2780. SEPARABLE routes — external could be blocked while keeping the upgrade's own access.
- Maintenance: set exec.go:257 ($HOME/statbus-maintenance/active); ON at service.go:4201 before destructive steps; cleared 4211/4227 (rollback) / 4828 (success) / 5684. @maintenance Caddy matcher 503s app + /rest (except auth) — HTTP/HTTPS ONLY; the Layer4 TCP DB proxy is NOT tied to it.
- DANGEROUS window = snapshot-taken → rollback-decision (migrations running, maintenance ON): browser + /rest gated, but direct Layer4 DB UNGATED → the data-safety hole.
- The 4828→4853 post-completion gap (maintenance lifts a hair before the `completed` UPDATE) is BENIGN — after the health check, no rollback pending.
- NO existing block-all-external-writes capability (no Layer4 conditional route, no pg_hba template, no DB read-only mode).

## Proposed lever
DB-level read-only toggle: ALTER DATABASE ... SET default_transaction_read_only = on before the destructive window, off after definitive completion. ONE chokepoint catching EVERY path at once (Layer4 + REST + auth) — no Caddy/Layer4 conditional-routing gymnastics. Persists across a crash (catalog setting) → the post-crash state is FROZEN (no external writes) until recovery decides → recovery always has a clean state. Caveat: the upgrade's own migration connection must be EXEMPTED (session SET transaction_read_only=off, or an exempt owner role); handle in-flight connections + superuser semantics.

## Payoff
- Closes the direct-PG write hole.
- Removes the data-loss RISK from rollback → relaxes STATBUS-039: under a guaranteed write-free window, rollback-under-uncertainty is data-safe, so recovery DIRECTION (forward-retry vs rollback) becomes an availability/disruption choice, NOT a data-safety one. Potentially collapses the "can't-verify → hold → human" branch.

## Cost
External WRITES blocked (reads OK) for the upgrade window. The common write paths (browser + REST uploads) are ALREADY gated by maintenance — this only adds the direct-PG path, so the incremental write-block is narrow. For an infrequently-upgraded registry, likely acceptable.

## Must be arc-tested
Behavior change to upgrade + recovery — prove via install-recovery arcs (STATBUS-071), incl. an arc that writes directly to PG mid-window and verifies the read-only block + clean rollback. Coordinate with STATBUS-109 (in-process backoff) and the parked byte/clean-restart decision.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 During the destructive+uncertain window, ALL external writes (browser, REST, AND direct Layer4 PG) are blocked while the upgrade's own migration session writes successfully (exempt) — proven by an install-recovery arc
- [ ] #2 The read-only state persists across a mid-window crash so the post-crash state is frozen until recovery decides
- [ ] #3 With the window guaranteed write-free, rollback-under-uncertainty is shown data-safe (no external writes to lose); STATBUS-039 'never restore on a guess' is re-evaluated and the recovery decision tree updated accordingly
- [ ] #4 Cost/acceptability of the read-only write-window documented (reads stay available; upgrades are infrequent)
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
## The recovery decision tree this re-grounds (current behavior — STATBUS-107 walkthrough, 11 paths)
- ACQUIRE-AND-RETRY (transient): `recovery-new-sb-retrying-db` (db unreachable → retry) · `recovery-new-sb-fetching-commit` (target commit not in clone → git fetch/deepen)
- KNOWN RECOVERY: `recovery-old-sb-never-swapped` (restart old) · `recovery-new-sb-completed-migrations` (finish bookkeeping) · `recovery-new-sb-pending-migrations` (one-shot rollback)
- STOP FOR A HUMAN: `recovery-stuck-needs-human` (acquire exhausted) · `recovery-unexpected-state` (unrecognized phase)
- HOUSEKEEPING: `recovery-nothing-pending` · `recovery-discard-corrupt-flag` · `recovery-clear-install-flag`
- EDGE (defensive): `recovery-binary-mismatch`

## Why the current model is conservative (and likely an under-ratified agent assumption)
"never restore on a guess" (STATBUS-039) + the whole "can't-verify → hold → human" branch exist ONLY because the direct-PG path is ungated during the destructive window (this ticket's hole) — so a rollback might erase a direct-PG integrator's writes. Close that hole and rollback loses nothing; the conservatism becomes unnecessary.

## Target model once the read-only window lands (110 + 109 compose)
With a guaranteed write-free window, rollback is ALWAYS data-safe. Recovery simplifies to:
- Transient (db down / commit missing) → QUIET in-process retry (STATBUS-109), no exit-noise.
- Forward logically possible → finish forward.
- Can't go forward (confirmed behind, or can't-verify and it won't resolve) → ROLL BACK safely → operator re-schedules.
- Truly unnameable (unrecognized phase) → stop for a human.
Net: the "can't-verify → hold → human" branch DISSOLVES into safe-rollback or quiet-retry; `recovery-stuck-needs-human` survives only for the genuinely unnameable.

## Decision needed (King ratifies — do NOT build without it)
Adopt the read-only window as the recovery-correctness FOUNDATION, vs keep the conservative never-restore model and merely reduce its noise via STATBUS-109? Architect recommends ADOPT: it closes the real hole and makes the system BOTH safer AND simpler, at the cost of a write-paused (reads-OK) window per upgrade — modest for an infrequently-upgraded registry.

## Path to conclusion
1. King ratifies the direction.
2. Architect writes the detailed design: toggle placement in executeUpgrade (on before destructive steps, off at confirmed completion), the upgrade-session exemption mechanism, in-flight-connection + superuser handling, and the simplified recovery decision tree.
3. Engineer builds; PROVE via install-recovery arcs (STATBUS-071): a direct-PG-write-mid-window arc + the simplified-recovery arcs.
4. Lock the registry (doc/upgrade-vocabulary.md) recovery names to the simplified set.
5. Formally supersede STATBUS-039 "never restore on a guess" with the read-only-window invariant; note it in doc/upgrade-timeline.md.
6. Land STATBUS-109 (quiet transient retry) as the composable partner.
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
PRIVILEGE-MODEL CORRECTION (verified vs running DB 2026-06-26): default_transaction_read_only AND transaction_read_only are BOTH context=user (USERSET); pg_parameter_acl is empty. => ANY role (not just admin) can `SET default_transaction_read_only=off` per-session and write. Demonstrated live: under RO a CREATE TABLE fails ('cannot execute CREATE TABLE in a read-only transaction'); after the same session flips the default off, it succeeds.

SO the read-only default is an ACCIDENT-GUARD, NOT an admin-gated lock: it REJECTS normal/accidental writes (error, not silent-write-then-lose) — which IS the data-safety bar (rollback stays safe vs the realistic threat: a careless direct-PG integrator) — but a DELIBERATE override by any user is possible (King-accepted: 'someone can work around it if they want to'). It is a speed bump, not a security boundary.

SIMPLIFICATION: the upgrade's own exemption is trivial — its migration session just does SET default_transaction_read_only=off for itself (USERSET, no special role/owner role needed). Remove the 'exempt owner role' option from the design; session-SET suffices.

IF a HARD boundary is ever required (regular users genuinely cannot write even deliberately; admin-only escape): use REVOKE write privileges from the app roles for the window, OR refuse their connections (Caddy Layer4 conditional route / pg_hba) — heavier, touches the RLS/grant model. DEFAULT plan stays accident-guard (cheap), per the King's stated intent; revisit only if the bar changes.

DECISION RATIFIED (King, 2026-06-26): build the read-only window as the ACCIDENT-GUARD (cheap path), NOT the hard admin-only lock.

PRINCIPLE (King's words): 'you cannot go wrong without intent; if you have intent you're allowed.' The system makes the dangerous thing impossible BY ACCIDENT and trivially possible DELIBERATELY. No accidental footguns; full deliberate control (the USERSET override IS the intended escape hatch, for the King to investigate when something stops).

NORTH STAR (why it matters): STATBUS upgrades run hands-off — an operator in Senegal/Uganda runs install and walks away. If recovery ever HOLDS for a human, that hands-off promise breaks → someone must physically intervene (fly out). The accident-guard keeps recovery AUTONOMOUS: accidental external writes blocked → rollback always data-safe → recovery self-decides (forward/rollback) → NO operator intervention. Autonomy is the goal; data-safety is the means.

NEXT: architect writes the detailed design (toggle on/off placement + the trivial session self-exemption) → engineer builds → arc-test (STATBUS-071). The hard admin-only mechanism is NOT needed; kept in notes only if the bar ever changes.
<!-- SECTION:NOTES:END -->

## Comments

<!-- COMMENTS:BEGIN -->
author: foreman
created: 2026-07-01 13:09
---
BUILD STARTED (recovery-core GO, King 2026-07-01; sequence 110→109→046→111). Engineer deep-read the read-only-window design vs live code (design :NNNN cites from 06-26 are STALE — verified real: setMaintenance=exec.go:241 filesystem-flag; connect=service.go:2783, reconnect=2900 routes through connect; ON/OFF sites 4252/4262/4278/4869/5814). NO diff yet — 2 load-bearing DESIGN GAPS surfaced to the architect (foundation-not-fix) before wiring, because building as-written ships a KNOWN-BROKEN upgrade (phase-3 migrations all fail):

F2 (critical): phase-3 `./sb migrate up` runs as a SUBPROCESS via migrate.go's own psql, OUTSIDE Service.connect() → under ALTER DATABASE default_transaction_read_only=on every migration write FAILS. Empirically confirmed: superuser NOT exempt. Design asserts 'the upgrade's migrations succeed' = internal inconsistency; also breaks forward-recovery + boot-migrate-after-crash-freeze. Fix options A/B/C; engineer+foreman rec B (migrate.go psqlEnv adds PGOPTIONS=-c default_transaction_read_only=off — uniform, migrate always a writer). Architect ruling pending.

F1: rollback() OFF (:5814) is NOT unconditional — the git-restore-fail ABORT terminal (os.Exit :5733) leaves the box DOWN (no reconnect, no live conn) so read_only can't be cleared there. Rec (i): accept read_only persists (symmetric with maintenance-stays-ON = crash-freeze intent), `./sb install` recovery clears at its terminal — CONTINGENT on confirming the recovery path reliably clears read_only. Architect ruling pending.

F3 (confirm): ON-before-DB-stop bakes read_only=on into the phase-2 backup → every rollback-restore is read-only, must be actively cleared. Race-avoidance tradeoff (ON-early, no write-slip gap). Architect confirm pending.

On the 3 rulings → engineer implements the coherent unit one pass → foreman review+commit → push→CI image→VM arc-run (071, the only oracle). Commit HELD.
---

author: foreman
created: 2026-07-01 13:21
---
RULINGS RESOLVED (architect, code-verified) — engineer GREENLIT to build the coherent unit in one pass. F2=B (ADDITIVE to the connect() self-exempt, not a replacement: connect() self-exempt covers the Service's own pgx writes [completed UPDATE / flag / recovery ground-truth]; migrate.go psqlEnv PGOPTIONS=-c default_transaction_read_only=off covers the migrate SUBPROCESS — post-swap+boot+forward-recovery+dev, uniform, no-op when guard inactive). F1=(i) accept read_only persists on the git-restore-fail ABORT (crash-freeze intent, symmetric with maintenance-stays-ON); recovery clears at both successful terminals (forward →:4869, rollback →:5814) — CONFIRMED no leak; read_only TRACKS maintenance. F3=confirmed: keep ON before the DB stop (race-avoidance closes the reconnect-inherits-read-write hole at phase-3 restart); backup carrying read_only=on is fine since every rollback-restore reaches :5814→OFF. Live setMaintenance(false) sites = :4262/:4278/:4869/:5814; ON at ~:4245 conn-close; pre-swap-abort OFFs after reconnect. 046-composition note (for 046's build, not 110): an at-target parked box decides read_only+maintenance TOGETHER. Build → self-check → foreman diff-review + commit → push→CI image→VM arc-run 071 (the only oracle).
---

author: foreman
created: 2026-07-02 06:25
---
COMMITTED 3ff119b8a (upgrade: read-only window during the destructive upgrade phase). 253 ins, 4 files: setDatabaseReadOnly (exec.go), connect() self-exempt + ON-before-stop + OFF at 4 live terminals (service.go), injectReadOnlyExempt host/docker split for migrate's write runners (migrate.go), readonly_exempt_test.go (host/docker delivery + merge-not-clobber + GUC-target). Foreman reviewed the full diff first-hand + re-verified build/vet/tests + the 4 new tests + the engineer's empirical DB validation (exempt session writes succeed, external blocked). Committed on foreman review — the architect went quiet overnight and a verified foundation shouldn't sit on a silent gate; both engineer refinements are sound + faithful: (a) F2=B EXTENDED to docker mode (docker compose exec doesn't forward host env — NECESSARY for production; scoped to migrate write runners, sparing interactive psql); (b) completion-OFF after the proven-live completed-UPDATE not the stale-prone :4869 (guarantees F1 no-leak; sub-second safe over-block window). STILL In Progress — AC#1/#2/#3 require the install-recovery VM ARC (STATBUS-071, the only oracle), which the foreman sequences next (interplays with the 118 harness-fix). Architect may still weigh in on the 2 refinements (reversible).
---

author: foreman
created: 2026-07-02 06:33
---
ARCHITECT REVIEW — BOTH DECISIONS CONFIRMED post-commit (first-hand diff read, 2026-07-02). Validates the foreman's own-review commit 3ff119b8a. (1) F2=B docker extension: bug-free + necessary — verified NO double `-e` clobber (injectPsqlAppName uses PGAPPNAME, injectReadOnlyExempt uses PGOPTIONS — distinct vars coexist after `exec`); host-mode merge correct (Go os/exec dedupes keeping LAST → exemption wins AND operator PGOPTIONS preserved); scoped to write runners only. (2) completion-OFF placed after the proven-live completed-UPDATE (not the stale-prone maintenance-off site): CONFIRMED + ACCEPT the sub-second window — do NOT close it, since co-locating maintenance-OFF would move it past the completed-UPDATE+NOTIFY and entangle the STATBUS-090 fix (real regression surface for a marginal UX gain). Terminals spot-check all correct; inline `./sb install` path covered (ExecuteUpgradeInline Execs on queryConn). Nothing to change. NEXT (unchanged): the install-recovery VM arc-run (STATBUS-071) is the only end-to-end oracle — sequence after the 118 harness fix lands so the arc targets a fixed controlled-B, not a moving HEAD.
---

author: foreman
created: 2026-07-02 18:24
---
⚠ SUSPECTED VM-ARC REGRESSION — the first real-VM exercise of the read-only window (arc run 28609876020, base includes 3ff119b8a) FAILED both working+failing arcs on HEALTHCHECK_REST_DOWN: after the upgrade's service restart, PostgREST admin /ready stayed 503 ('schema cache still loading') past the 5-min health window and the arcs timed out at 20 min; Jun-19 baselines passed the same step in ~69s. MECHANISM HYPOTHESIS (unproven): the design lifts read-only only AFTER the proven-live completed-UPDATE (comment #3), so waitForRestReady polls /ready while the app DB is still default_transaction_read_only=on — if anything in PostgREST's coming-up path needs a write (or a NOTIFY, which PostgreSQL forbids in read-only transactions), readiness wedges → forward step fails → every upgrade would now fail its health check. The rollback side worked (failing/B reached rolled_back correctly). EVIDENCE RUN DISPATCHED: mechanic local repro (restart rest under ALTER DATABASE ... read_only=on, capture REST's own error lines, mandatory RESET cleanup). If confirmed: fix design → architect (within the ratified accident-guard intent — candidate levers: exempt the authenticator role's session, or move the OFF point before the health check and re-derive the crash-freeze story), King nod, then arc re-run. AC#1-#3 remain UNCHECKED — correctly: the arc is doing its job.
---

author: foreman
created: 2026-07-02 18:40
---
REGRESSION CONFIRMED + MECHANISM NAMED (mechanic local repro, foreman-verified from the logs; full writeup tmp/mechanic-rest-readonly-repro.md). Baseline: REST /ready=200 in ~1s, schema cache 13.1ms. Under ALTER DATABASE ... default_transaction_read_only=on: /ready 503 at t+322s and wedged permanently — NOT slow, deadlocked. ROOT CAUSE: schema cache loads fine read-only; the wedge is PostgREST's dedicated LISTEN connection on the 'pgrst' channel (db-channel on by default; opens with target_session_attrs=read-write) — libpq rejects it at connect ('session is read-only'), retry loop capped at 32s forever, and v12.2.8's /ready requires that listener healthy. CIRCULAR DEADLOCK with this design: completion requires /ready=200 → /ready requires the listener → listener requires read-write → read-write returns only at completion. So as committed (3ff119b8a), EVERY upgrade wedges at the health check → in_progress + HEALTHCHECK_REST_DOWN forever — exactly the CI arc symptom. Cleanup verified (RESET + /ready=200 restored; note: the resetting session itself must SET session read-only off first to run the ALTER). Fix design dispatched to the architect (levers: role-level exemption for the REST db role [also satisfies the listener's read-write probe — to be verified empirically]; OFF-before-health-check; PGRST_DB_CHANNEL_ENABLED=false [suspect — the pgrst channel is the post-migration schema-reload path]). Design → King nod → build → arc re-run green = the proof.
---

author: architect
created: 2026-07-02 18:46
---
REST READ-ONLY REGRESSION — fix design → doc-023 (architect, 2026-07-02). Grounded first-hand (docker-compose.rest.yml + repro/baseline logs + code).

MECHANISM: PostgREST's PGRST_DB_URI has NO target_session_attrs, so its connection POOL works under read-only (schema cache loads). But its NOTIFICATION LISTENER connects with target_session_attrs=read-write (PostgREST v12 wants the LISTEN channel on the writable primary) → libpq runs SHOW transaction_read_only → 'on' → rejects at connect ('session is read-only') → retries every 32s forever → /ready 503 → health check fails. ONLY PostgREST is affected (target_session_attrs appears NOWHERE in our repo; our app/worker LISTEN as statbus_notify_<slot> with no read-write attr → they connect fine, only their writes freeze = intended).

FIX (lever a): ALTER ROLE authenticator SET default_transaction_read_only = off, delivered as a MIGRATION (role-GUC outranks database-GUC). Applies within the same upgrade (migrate step 10 precedes REST restart step 11). Preserves the accident-guard: PostgREST's external writes are ALREADY maintenance-503-gated (read-only was never the REST gate — its unique job is the direct-PG/Layer4 path, which uses OTHER roles). So exempting authenticator opens NO new external write path.

ROLE TABLE: authenticator EXEMPT (why: listener read-write check); anon/authenticated inherit (SET ROLE doesn't re-eval); queryConn+migrate already exempt (110); statbus_<slot>/notify (worker+app) + direct-PG integrators STAY GUARDED (the post-snapshot writers the window must freeze). WORKER answer: NOT exempt = correct (its writes are what rollback must discard) + it does NOT crash-loop (no read-write attr).

Crash-freeze INTACT (better than today: post-crash PostgREST now healthy, external still frozen by maintenance+read-only). Rejected: (b) lift-before-health (defeats crash-freeze), (c) PostgREST-config (breaks notifications, version-fragile). Ties to STATBUS-054 (v14 bump): role exemption is version-independent. PROOF = re-run 28609876020 green. Awaiting King nod → engineer builds the 1-line migration + doc/read-only-upgrade-window.md amendment.
---

author: foreman
created: 2026-07-02 18:50
---
FIX DESIGN EMPIRICALLY PRE-VERIFIED (mechanic, tmp/mechanic-rest-roleguc-check.log; design doc-023 updated with the deadlock-cut paragraph). With ALTER ROLE authenticator SET default_transaction_read_only=off + the window ON: /ready=200 at t+5s (vs permanent 503), ZERO 'session is read-only' listener errors, and a NON-exempt superuser session still write-blocked ('cannot execute CREATE TABLE/UPDATE in a read-only transaction') — the exemption is role-scoped, the accident-guard holds for every other role. Cleanup verified (pg_roles.rolconfig back to baseline, /ready=200 restored). BUILD-READY: awaiting the King's nod → engineer ships the 1-line migration + doc/read-only-upgrade-window.md amendment → arc re-run (same scenarios as 28609876020) green = closes this regression + 118's DoD.
---

author: foreman
created: 2026-07-03 11:47
---
🔴 ARC RE-RUN (28656025811) STILL RED — THE EXEMPTION-AS-MIGRATION HAS A STRUCTURAL FLAW ON SEED-RESTORED BOXES (mechanic classification + foreman hypothesis, architect verifying). Facts (tmp/mechanic-arc-28656025811.md): identical HEALTHCHECK_REST_DOWN on both forward-apply arcs DESPITE migration 20260703104910 present in base A and marked applied in the seed ledger; base-A installs healthy; the ROLLBACK arc PASSED (87s — the rollback path is fine); no immutability/hash errors anywhere (the stale-hash tail did NOT fire here). HYPOTHESIS (explains every observation incl. the mechanic's contradicting local repro): the arc VM installs by RESTORING THE SEED; ALTER ROLE settings live in the CLUSTER catalog which a database-level pg_dump never carries → the restored box's ledger claims the exemption applied while the role GUC does not exist → first upgrade turns the window on → REST restarts → no exemption → the original deadlock. Local dev worked because the migration RAN there. If confirmed: severity = EVERY seed-restored box's FIRST upgrade deadlocks — the fix must move to where cluster-level state is born (db init / post_restore.sql), and the general class 'cluster-level migration effects silently dropped by seed restore while the ledger claims applied' joins the stale-hash defect in the architect's unified seed-fidelity design (in progress, top priority). 110's AC proof remains blocked on that design landing + a green arc.
---

author: foreman
created: 2026-07-03 19:21
---
Exemption re-homed per doc-025 D (commit 98093f69f): migration 20260703104910 DELETED (was in no released tag; orphan ledger rows on boxes that ran it are skipped via findUpFile-miss). ALTER ROLE authenticator SET default_transaction_read_only=off now lives in migrations/post_restore.sql (re-armed on every migrate up, incl. seed-restored boxes — the pg_dump-cannot-carry-cluster-state root cause of the arc recurrence) AND postgres/init-db.sh (armed at cluster birth; ON_ERROR_STOP=1 so a failed arming statement cannot pass silently). 20240102000000's timeouts + safeupdate mirrors ride along in both homes. Proof-of-fix oracle: arc run 28679526112 — forward-apply upgrade must pass the REST /ready health check (no HEALTHCHECK_REST_DOWN recurrence).
---

author: foreman
created: 2026-07-03 19:40
---
🟢 ARC ORACLE GREEN (run 28679526112, foreman verified logs first-hand) — the doc-025 D re-home is PROVEN on seed-restored VMs: zero HEALTHCHECK_REST_DOWN occurrences; working arc A→B forward-apply reached state='completed' (t+55s) with the health check passing on ATTEMPT 1, code=200 (the exact leg that deadlocked in 28609876020/28656025811); failing arc: V_fail → 'rolled_back' (t+79s, healthy) then V_fixed → 'completed' (t+58s, healthy). AC1 CHECKED on combined evidence: exempt half proven in-arc (migrations applied + completed under the window on a real VM), external-block half proven empirically (comment 8: non-exempt sessions write-blocked while the role exemption is armed; mechanic tmp/mechanic-rest-roleguc-check.log). REMAINING, precisely: AC2 needs a crash-mid-window arc scenario (catalog persistence holds by construction — ALTER DATABASE survives crash — but unproven in-arc); AC3 has its rollback-evidence (failing arc data-safe rollback green) but awaits the formal STATBUS-039 supersession + decision-tree doc update (impl-plan step 5; the code half landed in 782ca2455's classify-then-act dispatch); AC4 = write the cost/acceptability paragraph.
---
<!-- COMMENTS:END -->
