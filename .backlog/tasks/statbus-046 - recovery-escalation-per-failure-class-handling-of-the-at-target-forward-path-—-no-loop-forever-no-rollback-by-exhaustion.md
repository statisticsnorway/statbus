---
id: STATBUS-046
title: >-
  recovery-escalation: per-failure-class handling of the at-target forward path
  — no loop-forever, no rollback-by-exhaustion
status: In Progress
assignee:
  - '@engineer'
created_date: '2026-06-12 22:15'
updated_date: '2026-07-03 22:02'
labels:
  - install-recovery
  - upgrade
  - recovery
  - design
  - needs-king-ratification
  - operator-ux
dependencies: []
references:
  - STATBUS-039
  - STATBUS-044
  - cli/internal/upgrade/service.go
  - doc/diagrams/upgrade-timeline.plantuml
  - doc/diagrams/upgrade-lifecycle.plantuml
documentation:
  - >-
    doc-021 -
    Recovery-escalation-—-the-per-failure-class-allowance-table-STATBUS-046.md
priority: high
ordinal: 46000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
KING DIRECTIVE (2026-06-13, direct): the "loudness" question cannot be answered in general — each kind of error has a different cause and needs its own sensible handling. Waiting for something that GETS ready deserves leniency; something that will NEVER get ready must fail fast and actionable; looping forever (rune's shape) is not an option — it eventually exhausts disk on top of the original problem. Each case goes in the diagram; each case gets a decided handling.

EMPIRICAL ANCHOR: systemd StartLimit demonstrably cannot bound this loop — rune restarted 10,229 times because the ~150s watchdog-kill cadence sits under the burst rate (≈4 starts per 600s window). The bound must be an UPGRADE-ATTEMPT budget owned by the recovery itself, not a unit-restart budget.

## The four failure classes (cause-based, classified AT THE CALL SITE — each postSwapFailure caller knows its own step's nature; the codebase already carries named Err* codes per step and isConnError discrimination, so the knowledge exists where the classification happens)

A. READINESS — the thing will become ready (DB container starting, app/REST warming, reconnect racing a restart). Leniency correct: in-attempt bounded waits (already exist: waitForDBHealth 30s, health-check 3 tries) + a SMALL cross-attempt forward-retry budget (proposal: 3 automated attempts), because a fresh attempt genuinely can succeed.

B. DETERMINISTIC — will never succeed by retrying (config-generate template error; registry 404 on a tag that should exist; SQL/constraint errors on the no-op at-target migrate; persistent app health failure past warmup = the running version cannot serve; CHECK violations — where markPgInvariantTerminal already fails fast today, the precedent). NO automated retry: park on FIRST occurrence with the named actionable error.

C. RESOURCE EXHAUSTION — never improves alone and RETRYING AMPLIFIES IT (disk full, connection-pool exhaustion). Park immediately with the named resource error; the attempt budget itself is what prevents the loop from CAUSING this class.

D. CRASH/KILL mid-attempt (watchdog SIGABRT, OOM, reboot) — the loop driver; the underlying cause is one of A/B/C but unknowable at death. Counts against the same budget: the attempt counter increments at attempt START, so a crash self-counts.

## PARK-DEGRADED — the mechanism that replaces loop-forever (proposal for ratification)

When the budget exhausts (A/D) or a B/C failure fires once: the row is PARKED — stays in_progress (forward-only preserved; rollback remains reachable ONLY via a positively-Behind verdict, never via exhaustion), gains a durable parked marker + attempt count + the named reason (proposal: recovery_attempts int + recovery_parked_at timestamptz columns — queryable, no enum churn; admin UI shows WHY). The service then SKIPS resume for the parked row on every boot/tick (one loud log line; degraded callback/siren fires ONCE), stays alive and idle — serving its normal loop, reachable by NOTIFY. No crash-loop, no journal/log bleed, no disk creep.

UN-PARK = exactly the product's two operator actions, nothing new: (1) re-trigger the upgrade (NOTIFY/apply — a fresh deliberate attempt with a fresh budget), or (2) ./sb install (a deliberate inline attempt). Each deliberate trigger is ONE attempt, not a loop.

## Per-step mapping (the diagram rows — each gets a decided handling)
- config generate → B (park first failure)
- docker pull → split by error: unreachable/timeout=A; manifest-unknown=B; disk=C
- db up / waitForDBHealth → A
- reconnect → A
- migrate (no-op at-target) → conn-error=A; SQL-error=B
- start services (step 11) → daemon hiccup=A; compose/config error=B; disk=C
- app health → warmup=A (in-attempt tries); persistent-past-warmup=B
- maintenance-off/archive/completion writes → conn=A; constraint=B (existing fail-fast precedent)
- watchdog/OOM/reboot death → D (budget self-count)

## Sequencing
1. King ratifies the classes, the per-step table, the budget value, and the park mechanics (or redirects).
2. Implementation (code + the row columns + the call-site classification).
3. DIAGRAMS UPDATED IN THE SAME COMMIT AS THE SHIPPED HANDLING (docs describe the present — never ahead of code): upgrade-timeline gains the per-class routing at the failure chokepoint; upgrade-lifecycle gains the parked representation of in_progress.
4. STATBUS-044's held scenario (3-postswap-resume-died-rollback, the pinned-kill shape) then asserts the DECIDED behavior: budget consumed → parked + named reason + unit alive-idle, NOT NRestarts climbing forever, NOT rolled_back.

RELATION: resolves the loudness fork that STATBUS-044 is holding on; builds on STATBUS-039's ground-truth routing (this design changes only HOW LONG and HOW LOUD forward is tried — never the direction).
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 King ratifies (or redirects) the four failure classes, the per-step mapping, the attempt-budget value, and the park-degraded mechanics
- [ ] #2 Implementation: call-site classification + attempt budget + park marker; rollback remains reachable ONLY via a Behind verdict, never via exhaustion; parked unit stays alive-idle (no crash loop, no disk bleed)
- [ ] #3 Both diagrams updated in the SAME commit as the shipped handling — every failure case visible with its decided handling
- [ ] #4 STATBUS-044's held scenario rewritten against the decided behavior and green
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
REFINEMENT (King review, 2026-06-13 — supersedes the description's class mechanics; .C and .D's budget-counting accepted as described):

.A — READINESS IS TIME-BOUNDED IN PLACE, NOT ATTEMPT-COUNTED. A retry budget was the wrong unit for waiting: each crash-retry re-pays the whole pipeline to reach the same wait. Class A gets a generous, NAMED, per-step time allowance sized to the worst legitimate case, size-scaled where the wait scales with data (DB crash-recovery WAL replay on a Norway-sized volume = many minutes; precedent: the size-scaled MigrateUpTimeout, STATBUS-012). The wait happens IN PLACE within the attempt.

.B — UNIFICATION: ALLOWANCE-PER-CASE, ZERO MEANS DETERMINISTIC. Classification is never by error text alone — it is (step, error, context) → a named allowance. The registry-404 example proves it: during publication (CI still uploading) it is a publication wait (allowance ≈ the upload process's honest worst case, minutes; precedent: markImagesFailed's manifest-timeout grace window in discovery); on an at-target RESUME the image demonstrably existed (containers run it) → no wait helps, external re-publish required → allowance ZERO. General form: "never gets ready" ≡ allowance = 0 (template/SQL/constraint errors are zero-allowance). ONE uniform mechanism everywhere: every failure mode carries a named allowance derived from its cause; ALLOWANCE EXPIRY → PARK, reason naming what was waited for and how long. The four classes become the derivation table for one number per case, not four mechanisms.

.D — THE NEXT ACTION AFTER A CRASH, in order: (1) systemd restarts the service (it has normal duties). (2) Boot recovery: row + flag → ground truth at-target → consult the attempt counter (incremented at attempt START — the crash self-counted). (3) Budget remaining → exactly ONE more forward attempt. Budget proposal: 3, sharpened: the flag records WHICH STEP the attempt died at; two consecutive deaths at the SAME step → park immediately (same-step-twice = deterministic-hang evidence = zero allowance per .B); different steps / reboot = environmental → remaining budget applies. (4) Budget exhausted → PARK: row in_progress + marker + attempt history + dying step; siren fires ONCE with that named story; service returns to its normal loop alive-idle. (5) After park the next action is a HUMAN's, via the product's two actions only — re-trigger or ./sb install — each deliberate trigger buys exactly ONE fresh attempt; the machine never resumes hammering on its own.

RATIFICATION REMAINING: the per-step allowance TABLE (each pipeline step × its failure modes × the derived allowance — the diagram rows), the D budget number (3) + same-step-twice rule, and the park marker columns. Implementation note: the flag already carries per-attempt state across restarts (Phase, BackupPath) — the dying-step record and attempt counter extend the same persisted-flag pattern; the row mirror (recovery_attempts, recovery_parked_at) serves install/UI/queries.

DETAILED ALLOWANCE-TABLE DESIGN WRITTEN (architect, 2026-07-01) -> doc-021. Fills the three ratification-remaining pieces: (1) the per-step allowance TABLE (grounded in the current waits: waitForDBHealth 60s exec.go:1022/1057, MigrateUpTimeout 30m size-scaled, healthCheck retries + waitForRestReady, WatchdogSec=120; systemd StartLimitBurst=5/600s + RestartSec=30 provably can't bound the ~160s/cycle rune loop); (2) the D attempt-budget=3 + same-step-twice->park rule (dying step recorded on the flag; counter increments at attempt START so a crash self-counts); (3) the park-marker columns recovery_attempts int + recovery_parked_at timestamptz. Unified mechanism = one named allowance per (step,error,context): A=readiness time-bound-in-place-size-scaled, B=deterministic=0->park, C=resource=0->park, D=crash->budget. PARK-DEGRADED replaces loop-forever (row stays in_progress, forward-only preserved, rollback only via positively-Behind, un-park only via the 2 operator actions). Composition: 039 sets direction / 046 governs how-long+how-loud before park; 110 makes pre-completion rollback safe / 046's park is the at-target regime; 109 = the class-A in-place wait generalized per step. Sequenced after 110/109 in the recovery-core build. READY FOR KING RATIFICATION (3 asks in doc-021 §Ratification).
<!-- SECTION:NOTES:END -->

## Comments

<!-- COMMENTS:BEGIN -->
author: foreman
created: 2026-07-02 06:27
---
DESIGN WRITTEN → doc-021 (architect, 2026-07-01) — recovery-core unit 3 (sequence 110→109→046→111; 110 COMMITTED 3ff119b8a). Allowance table: per-(step,error,context) allowance — A=readiness (time-bound in place, size-scaled), B=deterministic→park, C=resource→park, D=crash→budget. Attempt budget=3 + same-step-twice→park (counter increments at attempt START so a crash self-counts). Park columns: recovery_attempts int + recovery_parked_at timestamptz; PARK-DEGRADED replaces loop-forever (row stays in_progress, forward-only preserved, ROLLBACK only via a positively-Behind verdict — NEVER exhaustion; un-park only via the 2 operator actions). Composition: 039=direction, 046=how-long/how-loud forward before park (never direction), 110=pre-completion rollback data-safe, 046-park=the at-target/post-completion regime (users+integrators live → can't safely roll back → park not loop), 109=class-A in-place wait generalized. READY FOR KING RATIFICATION — 3 concrete asks in doc-021 §Ratification: (1) the allowance values, (2) budget=3 + same-step-twice, (3) the 2 park columns. NOT started (unit 3, after 110-verify + 109). Verify via 071 arcs (STATBUS-044's held scenario = budget-consumed → parked+named+alive-idle, + per-class A/B/C/D arc).
---

author: architect
created: 2026-07-02 18:24
---
doc-021 EXPANDED with THE STEP LIST (architect, 2026-07-02) — answers the King's ratification gap ('which steps are covered, transient or deterministic'). Grounded first-hand vs master HEAD (executeUpgrade 3983, applyPostSwap 4574, rollback 5650). Per-step walk in 5 phases, each step: (a) what runs (b) failure classes A/B/C/D + concrete example (c) what a class-D crash means (d) inside/outside the budget.

BUDGET BOUNDARY (new ask #4, made explicit): counted from the FLAG WRITE (Phase 1.1, service.go:4140) through the COMPLETED-WRITE + FLAG REMOVAL (Phase 4.2–4.3, :4957/:5001). Phase 0 pre-flight (before the flag) and Phase 5 post-completion cleanup (after flag removal) are OUTSIDE. A Phase-1 (pre-swap) exhaust ROLLS BACK (data-safe via 110's stopped-DB snapshot); a Phase-3 (post-swap at-target) exhaust PARKS (can't roll back — the rune-loop regime). Awaiting King ratification of asks 1–4.
---

author: foreman
created: 2026-07-03 19:05
---
RATIFIED BY THE KING (2026-07-03, decision D3 — verbatim record on STATBUS-127 comment 2). All four asks approved: allowance values as proposed (tunable at build/arc); crash budget = 3 counting PROCESS DEATHS only (temporary errors get time-budgeted backoff, never counted attempts; permanent park on first) + same-step-twice → park immediately; park columns recovery_attempts + recovery_parked_at; the budget boundary = flag-write (service.go:4140) through completed-write + flag removal, phases 0 and 5 outside. The bounce-then-ratify loop that got here: the King required the per-step walk (doc-021 now carries all 44 operations with file:line and per-step classes) and the precise temporary/permanent/crash class model. BUILDABLE after the arc lane validates the 110 seed-fidelity fix + 109 (recovery-core order 110→109→046→111 preserved); the designated verification vehicle is STATBUS-044's held scenario (parked + named reason + alive-idle, not NRestarts-climbing).
---

author: architect
created: 2026-07-03 20:02
---
BUILD SEQUENCING (architect, 2026-07-03, pre-staged per foreman; doc-021 is the spec, D3 the ruling — this orders the work + flags the review-critical subtleties):

**Slice 1 — the park substrate + D budget (ship first; alone it kills the rune-loop class).**
(i) Migration: `public.upgrade` += `recovery_attempts int NOT NULL DEFAULT 0`, `recovery_parked_at timestamptz`, + the named reason as a queryable column (`recovery_parked_reason text`) — SCHEMA change ⇒ doc/db + types regen in the same held package (mandatory pairing), and mind the migration-set template rebuild locally. (ii) Flag += the dying-step field (extends Phase/BackupPath — service.go:4140 writeUpgradeFlag + recoverFromFlag readers). (iii) Increment-at-attempt-START on every flag-owned resume (crash self-counts; a DEAD process needs no post-hoc bookkeeping) — D3 sharpening: count PROCESS DEATHS ONLY; class-A waits never consume attempts. (iv) Budget=3 + same-step-twice→immediate: Phase-3 exhaust → PARK, Phase-1 exhaust → ROLLBACK (data-safe). (v) Park semantics: row stays in_progress; boot/tick resume SKIPS parked rows with ONE loud line; callback/siren fires ONCE (persist a fired-marker so it doesn't re-fire per boot); unit stays alive-idle + NOTIFY-reachable. (vi) Un-park = the two deliberate operator actions only, each = exactly one fresh attempt: RESET recovery_attempts (+ clear parked_at/reason) on a deliberate trigger, never on self-resume.

**Slice 2 — B/C call-site classification (park-on-first) at the seven Phase-3 sites** (doc-021 step list 3.1–3.7): config-generate error (B), pull 404-at-resume (B) vs disk (C), migrate deterministic SQL (B), start-services compose error (B)/disk (C), health can't-serve-past-warmup (B). CLASSIFIER DISCIPLINE (the doc-022 lesson): prefer STRUCTURED signals — SQLSTATE, exit codes, docker error classes — over English-substring lists (persistentStepSignatures over-matched before; that is why forward-step unknown→stop was deferred). Context is load-bearing: the SAME 404 is class A during publication, class B at at-target resume — the classification input is (step, error, context), never error text alone. Every park writes the NAMED actionable reason.

**Slice 3 — class-A allowance re-sizing (smallest; can trail).** Most waits already exist (109 backoff, healthCheck retries, waitForDBHealth 60s exec.go:1022/1057): work = size-scale db-health to volume worst case, add the publication-wait allowance for pull-404-during-publication. Values are D3-tunable at build/arc.

**Per-slice invariants (I review against these):** diagrams (upgrade-timeline.plantuml per-class routing + upgrade-lifecycle.plantuml parked-in_progress) land IN THE SAME COMMIT as the handling they describe; rollback stays reachable ONLY via a positively-Behind ground-truth verdict, NEVER by exhaustion (039's direction rule — 046 governs how-long/how-loud, never direction); the rollback pipeline's own resumes count the budget with same-step-twice → the restore-broke HUMAN stop (not park-and-retry).

**Verification vehicle:** STATBUS-044's held 3-postswap-resume-died-rollback scenario rewritten green (parked + named reason + alive-idle; NOT NRestarts climbing, NOT rolled_back) + per-class arcs A/B/C/D under STATBUS-071. The run is the only oracle — reconcile allowance values there.
---

author: foreman
created: 2026-07-03 20:19
---
SLICE-1 PROGRESS + DESIGN SEAM RULED (2026-07-03 evening). BUILT so far (uncommitted, engineer): migration 20260703210000 (the three park columns — applied to dev, seed, and test template; tester verified \\d output), recovery_escalation.go (pure decision core: budget + same-step-twice + terminal routing; machine-string step identifiers, never English), 5 green tests. ARCHITECT RULING on the one seam: CONFIRMED — the core routes a terminal via a caller-supplied canRollBack BOOL (computed by the 039/ground-truth layer: pre-swap or positively-Behind = true, at-target = false); passing the phase into the core would duplicate direction knowledge — the same gate/action-divergence class the 055 fix killed. THREE PINS for the wiring: (1) name the budget in DEATHS not attempts (deaths = attempts−1; 3 deaths = terminal; prevents a future 'fix' of an off-by-one that isn't one); un-park resets the counter ONLY on the two deliberate operator triggers; (2) WRITE-AHEAD step recording — the flag's dying-step is written before each step starts, so a SIGKILL leaves the step name behind and same-step-twice can actually fire; (3) rollback-pipeline resumes reuse the core but map terminal at the CALL SITE to the restore-broke human stop — the core's {continue, park, rollback} vocabulary does not widen. Remaining: service.go wiring (flag fields, increment-at-start, step instrumentation, park skip + once-only siren, un-park reset), diagrams in the same commit, doc/db + types pairing (now unblocked by the tester's refresh).
---

author: foreman
created: 2026-07-03 20:32
---
INSTALL UN-PARK RULED (architect, 2026-07-03): option (a) — the deliberate ./sb install resets the park marker in the INSTALL LADDER (cli/cmd/install_upgrade.go crash-recovery Part 2, after LoadConfigAndConnect succeeds, before RecoverFromFlag); the parked-skip in the service resume path stays UNCONDITIONAL (automatic resumes never un-park — a deliberate-bool through the shared resume path would couple it to caller intent at every call site, the same divergence class 055 killed). Scope pins: (1) PARKED-ONLY reset (recovery_parked_at IS NOT NULL) with a loud named line — a crashed-but-not-parked row keeps its attempt count so install-driven crash cycles still park on budget exhaustion; the NEXT install after a park gets the fresh budget; (2) ONE shared reset helper (columns + live-upgrade guard) with two thin keyed wrappers (by commit_sha for re-schedule, by id for install) so the two operator triggers can never drift; (3) no new locking — the install-vs-service race serializes on the existing flag/flock machinery, either runner's fresh attempt satisfies the contract. Siren confirmed per-park-event (no fired-marker to clear; re-park after a failed fresh attempt correctly sirens again). GAP THIS CLOSES: without it, a parked row would silently swallow the operator's canonical run-install-again recovery action — the hands-off deployment contract. Engineer wiring now; then the whole slice-1 package → architect hands-on review → foreman review → commit.
---

author: foreman
created: 2026-07-03 20:55
---
SLICE 1 COMMITTED + PUSHED: c1c4cbb7a (12 files, +596/−18; the pre-commit hook folded the regenerated diagram SVGs into the same commit). The loop-forever class is killed in code: park substrate (3 columns + doc/db/types pairing), write-ahead dying-step on the flag, pure escalation core (RecoveryDeathBudget=3 process deaths; same-step-twice terminal early; canRollBack routing), parked-skip→increment-at-start→escalate→park (row stays in_progress, siren exactly once per park event via freshlyParked), and un-park on ALL THREE deliberate trigger surfaces with fresh budget: RunSchedule (CLI), onScheduledNotify (NOTIFY apply — edit 6, which also deliberately fixed the pre-existing NOTIFY-on-live-upgrade row clobber), and the install path (hard-fails actionable if the reset can't be written). Six ruled edits all in (architect APPROVE + foreman first-hand; one foreman ruling overruled by architect with the 42703 self-ship bootstrap case — fail-open documented at the site with a do-not-fix warning). Deferred, named: rollback-pipeline resume mapping (slice 1b). ACs: #1 was ratified (D3); #2 substrate half DONE (call-site B/C classification = slice 2, now building); #3 satisfied for slice-1 scope (diagrams in-commit, B/C marked slice 2); #4 open (the held scenario rewrite — the arc is the oracle). SLICE 2 DISPATCHED to the engineer (classification table first as reviewable spec; structured signals only). The push's seed job doubles as the first DELTA-migrate incremental build (run 28682974989, operator watching).
---

author: foreman
created: 2026-07-03 21:03
---
SLICE 2 FULLY SPECCED (architect rulings Q1-Q5, 2026-07-03 late evening; engineer building — classification table at tmp/engineer-046-slice2-classification-table.md is the spec). Q1: unknown signal → class A (budget + same-step-twice bound it — same-step-twice parks an unknown-deterministic error on its SECOND occurrence, faster than the budget; the doc-022 unknown→stop was for a classifier with NO bound). Q2: exact canonical text markers allowed under four pins — protocol/kernel constants only with cited source (OCI MANIFEST_UNKNOWN verbatim; strerror(ENOSPC)), always conjunctive (step + non-zero exit + marker), park only on positive match (a miss degrades to bounded leniency — under-match can never wrong-park), one marker per class per site unit-tested against verbatim strings. AMENDED: disk C-signal primary = local statfs pre-check (mirrors the Phase-0 gate), ENOSPC marker as in-flight backstop; manifest/404 markers stand, no network pre-probe (TOCTOU). Q3: one site-parameterized reason template for image-not-published (one operator playbook entry). Q5 (the subprocess-boundary finding — engineer verified exit codes don't sub-classify; SQLSTATE never crosses): sb migrate up ENCODES its failure class in documented exit codes — 0 success / 1 unclassified→A / 20 deterministic (psql exit 3 under ON_ERROR_STOP)→B / 22 resource (SQLSTATE class 53 via psql VERBOSITY=verbose documented field)→C; named consts shared migrate↔service; stderr rides the park reason as DATA never as classifier; 22 deferrable briefly (B and C both park-on-first). This contract is also the substrate the deferred 109 forward-step classifier waited for. Added table row: migrate disk-full 53100 → C. Build order: config-generate (B, cleanly structured today) + framework first; migrate exit-code contract; docker markers after recon confirms verbatim strings.
---

author: foreman
created: 2026-07-03 21:32
---
SLICE 2 COMMITTED + PUSHED: f70ede5e4 (11 files, +635/−12; diagram SVGs folded in by the hook). Both reviews green (architect APPROVE AS-IS, zero edits; foreman first-hand). THE COVERAGE RECORD (per architect — the durable home for the classification table, superseding tmp/engineer-046-slice2-classification-table.md):

SHIPPED park-on-first — 3.1 config-generate: B via exit≠0 non-timeout (templates from .env.config, no network/DB — deterministic by nature). 3.5 migrate: B via the NEW exit-code contract (migrate/exit_codes.go: 0 success / 1 unclassified / 20 deterministic / 22 resource; producer maps psql's documented exit 3 under ON_ERROR_STOP → process exit 20; consumer reads ONLY the exit code). 3.2 image-pull + 3.6 start-services: C via local statfs pre-check (existing DiskFree, 5 GB floor — the will-this-step-fail bar vs install's 100 GB should-we-install bar) parking BEFORE the step, plus the ENOSPC stderr-tail backstop (kernel-authored strerror survives daemon rewrapping) via the new bounded capture variant — streaming unchanged.

DEFERRED with rulings at each site — manifest-404→B (3.2/3.3): live probe proved the daemon REWRAPS OCI MANIFEST_UNKNOWN into generic prose; ships unknown→A (persistent 404 parks in 2 deaths via same-step-twice); promotes only after a real-surface Linux sample, and if that is also generic it stays A PERMANENTLY (post-failure manifest-inspect probe = the only future alternative, not speculative). Migrate 22/C: psql VERBOSITY SQLSTATE-field plumbing. Health-past-warmup B (3.7): couples to the warmup allowance — slice 3's first item. 3.6 compose-config-B: no structured signal identified; unknown→A is its honest permanent home unless one appears. 3.3 db-up / 3.4 reconnect: class A unchanged.

Default rule shipped: unknown structured signal → A — safe because an error-exit counts as a death, so same-step-twice parks an unknown-deterministic failure on its SECOND occurrence (faster than the budget). Park disposition stays ground-truth-gated (Behind→rollback, else park + once-per-event siren). IN FLIGHT: mechanic building the park-scenario rewrite (3-postswap-resume-died-parked.sh visible in tree, uncommitted); slice 3 (allowances) + slice 1b (rollback-pipeline mapping) remain.
---

author: foreman
created: 2026-07-03 22:02
---
CLOSING UNIT COMMITTED + PUSHED: 886c79293 (6 files, +384/−16; no schema change) — the 046 BUILD SURFACE IS COMPLETE. Slice 1B: rollback crash-resume bound — ONE shared never-reset death counter, rollback terminals ONLY on two consecutive rollback deaths (never exhaust — a pre-swap exhaust routes to rollback and must get its re-attempt); pure sibling rollbackResumeIsTerminal(step, prior); the flag ROLLS prior←Step then stamps Step=rollback so the handoff free-pass holds by construction; terminal → restore-broke human stop with actionable message + recovery callback; hard bound 3 forward + 2 rollback = 5 deaths. NOTE FOR THE RECORD: both closing reviews (architect + foreman) independently caught the same off-by-one in the first cut (terminal after ONE rollback death — a single transient mid-restore OOM would have summoned a human with zero retries) — fixed pre-commit; the dual-review architecture earning its cost on recovery-critical code. Slice 3a: health-past-warmup → B park-on-first (verified: waitForRestReady's 5-min /ready warmup runs BEFORE the RPC loop — exhausted = genuinely can't serve). Slice 3b: PostSwapDBHealthTimeout=5min (WAL-replay-aware, generous-fixed doctrine). Slice 3c (mechanic-built, engineer-reviewed): images-ready CLAIM GATE at BOTH claim sites — building→loud wait + immediate re-probe (closes the 6h-starvation gap), failed→loud actionable no-op, past-grace→claim-anyway loud (delay-never-wedge); grace = the hoisted manifestTimeout shared with verifyArtifacts by construction; pure gate with conservative default; also fixes the latent wart where a fresh push was immediately claimed + half-published images pulled. Plus the required statfs log line. REMAINING on 046: the deferred classifier arms (inventoried comment 9) and the EMPIRICAL CAPSTONE — the park-scenario VM run (r3 in flight, task bj81y4tz6). AC#2 substantially complete pending the arc; AC#3 diagrams current; AC#4 = the VM run.
---
<!-- COMMENTS:END -->
