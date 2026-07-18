---
id: STATBUS-192
title: >-
  selfheal-serve-proven: completeInProgressUpgrade marks 'completed' without
  serving — the flagless self-heal must converge the BOX, not just the row
status: In Progress
assignee:
  - engineer
created_date: '2026-07-15 08:52'
updated_date: '2026-07-18 13:44'
labels:
  - upgrade
  - install-recovery
  - defect
  - safety-core
dependencies: []
priority: medium
ordinal: 193000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
> NORTH STAR: 'completed' means THIS VERSION VERIFIABLY SERVES (the STATBUS-160 doctrine) — at EVERY writer, including the flagless self-heal. A box must never carry a completed ledger row while its app is down.
> FOUND: 2026-07-15, the flagless-selfheal successor arc's U5 set-difference check (STATBUS-071). The arc kills a real upgrade at-target BEFORE StartServices, truncates the flag, and the flagless boot's completeInProgressUpgrade (service.go:2860) converges the row to 'completed' — with app/worker/rest still DOWN. Code-verified: the routine checks DB health only (waitForDBHealth 30s → 'failed' on miss) + observed-state at-target; it never starts app services and never runs the app health gate. The deleted interim scenario's assert_health_passes was ILLUSORY coverage — it passed because the fabricated row sat on an already-running box, not because the self-heal produced a serving one.
> WHY IT MATTERS: real producers of the flagless state exist (corrupt-flag removal, tmp/ flag loss — the r19-ruling producers) at any pipeline point, including pre-StartServices. A box that self-heals to completed-while-dark lies to the operator AND to STATBUS-170's convergence poll (green = row completed — the poll inherits the lie). Broader than the services-down corner: even with services up, an unparked broken-app at-target row self-heals to completed with zero serving proof.
> COMPLEXITY: engineer, medium — the fix mirrors machinery that already exists.

FIX SHAPE (architect): completeInProgressUpgrade's completed write becomes SERVE-PROVEN — after the existing DB-health + observed-state-at-target gates pass, run the same tail resumeNewSb runs: bring the app set up (compose up), run the SAME app health gate, maintenance off, THEN completed. A health failure routes to the SAME disposition resumeNewSb uses (park-at-target via parkForDeterministicFailure — named reason, one siren, alive-idle) — never a completed lie, never a silent dark box. The 135 parked-skip guard stays first (a parked row is untouched).

ORACLE: the flagless-selfheal successor arc gains the health assert (assert_health_passes after convergence) — the exact assert whose set-difference absence surfaced this ticket; the arc's kill-before-StartServices construction is the natural RED→GREEN proof (red on current code, green with the fix).
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 completeInProgressUpgrade brings the app set up + runs the app health gate + maintenance off BEFORE the completed write; DB-health + observed-state gates unchanged; 135 parked-skip stays first
- [ ] #2 Health failure routes to park-at-target (parkForDeterministicFailure: named reason, one siren, alive-idle) — never completed-while-dark, never a silent dark box
- [ ] #3 The flagless-selfheal successor arc gains assert_health_passes after convergence — RED on pre-fix code, GREEN with the fix (the run is the oracle)
- [x] #4 Architect frozen-diff review before commit (recovery safety-core)
<!-- AC:END -->

## Comments

<!-- COMMENTS:BEGIN -->
author: foreman
created: 2026-07-16 12:55
---
King ruling (2026-07-16): STATBUS-192 GATES the stable cut. Fork resolved as 'finish tail first' — no cut until the serve-proven completed write ships and is proven. Fix as ruled: completeInProgressUpgrade's completed write becomes serve-proven — run resumeNewSb's tail (app setup → app health gate → maintenance off → completed); health failure → park-at-target. RED→GREEN oracle: the flagless-selfheal arc's kill-before-StartServices run. Engineer builds, architect frozen-diff review.
---

author: architect
created: 2026-07-18 12:49
---
FIX SHAPE refinement (architect, 2026-07-18, pre-build — premises verified at writing time). Three additions the build must carry; my AC#4 frozen-diff review checks them.

1. THE TAIL INCLUDES THE READ-ONLY WINDOW LIFT. The window engages at step 2 (service.go:5305) and lifts only at completion (:6213) or rollback (:7524). Every flagless at-target orphan therefore carries window ON. Today's heal completes without lifting it, so the boot backstop clearStaleReadOnlyWindow (:2217) fires ROUTINELY on this path — but its firing is defined as an investigation trigger (:3521 'RECURRENCE INDICTS'), and the tick-belt caller (:2312) has no backstop after it at all. A completed box that rejects every write with 25006 is 'a broken box masquerading as healthy' (:6209). Build: after the completed write lands, run terminalExec(windowOffSQL) with the same COMPLETION_READ_ONLY_WINDOW_LIFTED escalation as :6213-6220. Ordering as in applyNewSbUpgrading — completed UPDATE first (senior truth), then the flip, loud on failure.

2. HEALTH-FAIL PARK MUST END IN THE STANDARD PARKED SHAPE: parked row + flag file on disk + flock free + unit alive-idle. Premise: UnparkByID's sole caller is install_upgrade.go:315, inside runCrashRecovery, reachable only via StateCrashedUpgrade (flag present, flock free). A park from THIS caller writes no flag (parkUpgrade is row-only, :6528), so the parked row would be invisible to the install ladder (box probes nothing-scheduled) — while the park's own operator message (:5628) promises 'run ./sb install for a fresh attempt'. The promise must be kept. Build: on the health-fail path, BEFORE parking, materialize a faithful flag — the synthesized-flag genre already ruled for the flagless rollback (:3001-3019): ID/CommitSHA from the row, Trigger 'recovery', Holder service, Phase PhaseNewSbSwapped (the at-target truth; next boot's recoverFromFlag routes it to resumeNewSb, whose parked-skip holds alive-idle, flag kept), BackupPath from the row (persisted pre-migrate, so populated at-target). Write the file directly (json.MarshalIndent + os.WriteFile), do NOT acquireFlock — the flock is the destructive-work mutex and this pass is going idle; flag-present + flock-free is exactly the un-parkable state, and install's takeover quiesces the unit first by design. Order: flag write, THEN park row — a crash between the two leaves an ordinary crashed-upgrade, never the invisible shape. If the flag write itself fails (ENOSPC is a live park cause), park anyway and warn loudly that install-un-park is unavailable and scheduling a fix release remains the trigger (degrade, don't block the park). Consequence: the unconditional defer removeUpgradeFlag() (:2907) must NOT strip this flag — set a named parkedExit bool on the park path and check it in the defer. Do not re-read park state in the defer (a failed read defaults wrong); the bool is the truth of THIS pass. 135's own principle: parked rows keep their flag.

3. COMPOSE-UP FAILURE MIRRORS THE EXISTING THREE-WAY (:6074-6093): diskPrecheckReason → park; classResource (ENOSPC backstop) → park; anything else → newSbUpgradingFailure, which at-target reduces to recordInProgressFailure — row stays in_progress, forward retry on the next tick/boot. Never completed, never a new hand-rolled disposition.

Build notes (review checklist, not new rulings): (a) the tail runs with a LIVE progress log — today appendLog is closed at :3027 right before the completed write; the health/park narrative must reach the on-disk log served at /upgrade-logs. (b) 135 parked-skip stays first, unchanged. (c) supersede/callback/pruneBackups ordering stays post-completed as today. (d) AC#3: the arc adds assert_health_passes after convergence; compose-up + waitForRestReady warmup now sit inside CONVERGE_BUDGET_S=600 — do not pre-tune, the run is the oracle; if it times out, the budget is the first suspect, not the fix.
---

author: architect
created: 2026-07-18 13:11
---
AC#4 FROZEN-DIFF REVIEW (architect, 2026-07-18) — verdict: APPROVE WITH AMENDMENTS. The core fix is faithful to the ruled shape + comment #2; three must-fix amendments below, then a delta re-review of just the amended hunks. The freeze holds until then.

APPROVED AS BUILT: parkedExit-guarded defer + the re-anchored 135 structural test (anchor 'if !parkedExit {' is unique in the body, order assert preserved); parkAtTarget closure — flag-first ordering, direct JSON write without flock, ENOSPC degrade path, and the MkdirAll addition (approved: the tmp/-loss producer implies the dir itself may be gone); three-way compose disposition exactly mirroring :6074-6093; restoreTargetSHA=\"\" per the 077 convention; live progress log incl. the NewUpgradeLog fallback (verified safe: ProgressLog.Write syncs every line to disk, progress.go:245-246, so the open-log bundle read on the completed-write-failure branch loses nothing); windowOff escalation byte-mirror with named invariant; maintenance-off placement; arc header rewrite. Note for the record: setting parkedExit=true before the row park is CORRECT — if the park row-write then fails, [flag + in_progress row] is an ordinary crashed-upgrade next boot, self-correcting.

MUST-FIX 1 — WATCHDOG COVERAGE FOR THE TAIL. The serve-proof compose runs inside the daemon's ACTIVE phase under WatchdogSec=120 (READY=1 was emitted before recoverFromFlag, service.go:2222). Subprocess output lines only bump() the progress gate (PrefixWriter onLine — progress.go:263); they do NOT sd_notify. applyNewSbUpgrading survives its own step 11+12 via the GATED runGatedWatchdogTicker goroutine (:5874, covering reconnect→migrate→step11→step12); the boot-migrate site wraps itself the same way (:2056). completeInProgressUpgrade's new tail has NO ticker: a compose that stays >120s between our explicit Write calls — real-world whenever images were pruned since the crash (--no-build then pulls from the registry for minutes) — gets the daemon SIGKILLed mid-heal → restart → re-enter → repeat → StartLimit (10 in 600s) → unit down, box dark. A kill loop introduced by the fix, and the arc CANNOT catch it (in the arc's genesis the kill site is after step 9's pull, so images are local and compose is seconds). Fix: wrap the tail (from the diskPrecheck through healthCheck's return) in runGatedWatchdogTicker with appendLog as the gating progress + the same applyNewSbUpgradingStallThreshold/cadence; cancel+join via ONE deferred closure (safe here — every post-ticker path returns from the function; the Run() no-defer rationale at :2038 does not apply). A genuinely hung compose is bounded by its own 5-min command timeout → error path → forward retry; the gate closing on a real hang is the watchdog working. Update the 'Three callers' note in watchdog.go:207 to four.

MUST-FIX 2 — assert_health_passes IS TRANSPORT-ILLUSORY ON THESE VMs; THE RED ARM CANNOT GO RED. The probe (assertions.sh:22) is `curl http://127.0.0.1:3010/rest/` with Host 127.0.0.1. The VMs install CADDY_DEPLOYMENT_MODE=development + SITE_DOMAIN=statbus-test.local (vm-bootstrap.sh:269-270); the development Caddyfile's site keys are http://statbus-test.local, statbus-test.local, http://proxy, and http://127.0.0.1:19999 (caddy/templates/development.caddyfile.tmpl:105,193,199,206). Host 127.0.0.1 on the :3010 bind matches NONE → Caddy answers its no-matching-site EMPTY 200 — the exact mechanism established empirically in the C-rollback run-3 ruling (2026-07-15; that arc's probe moved to :3013 for this reason). Pre-fix state at assert time: proxy UP (step 3 keeps the proxy running for the maintenance page; the kill never stopped it), app/worker/rest DOWN → the probe hits the live proxy → 200-empty → the assert PASSES on a dark box. The RED→GREEN oracle as frozen has no RED. Fix the SHARED helper, not a bespoke probe: assert_health_passes gains -H \"Host: <SITE_DOMAIN>\" (statbus-test.local; read it from the VM's .env.config or accept it as an env default) so the request matches http://{{.Domain}} and traverses handle @rest → reverse_proxy rest:3000. Down rest → 502 → RED correctly; healthy rest → PostgREST root 200 → GREEN. This is a fleet-wide STRICTNESS INCREASE on a shared gate: any other scenario that was illusorily green with a dark app will now fail — that is the system working (test-to-know), but foreman should expect it when the suite next runs.
---

author: architect
created: 2026-07-18 13:12
---
AC#4 review, part 2 (architect, 2026-07-18) — must-fix 3 (the engineer's open question, ruled), two minor amendments, one out-of-scope observation.

MUST-FIX 3 — REFINEMENT-1 COVERAGE: THE DISCRIMINATOR IS THE BACKSTOP'S SILENCE, NOT A WRITE PROBE ALONE. The engineer's instinct is right that the GET can't cover the window lift — but a plain write probe can't either: pre-fix, the boot sequence runs clearStaleReadOnlyWindow (:2217) right AFTER completeInProgressUpgrade (:2207), so the backstop clears the window and a write probe is GREEN on both arms. The behavioral discriminator is the backstop line itself: on the GREEN run the journal must NOT contain 'STATBUS-163 BACKSTOP' within the arm-scoped window (the arc already has the SINCE anchor + journal_has helper — assert the NEGATIVE). That enforces refinement 1 directly: the tail's own lift ran, the backstop stayed quiet, its firing remains an investigation trigger. ALSO add the cheap end-state write probe as a belt — fresh ./sb psql session: BEGIN; UPDATE public.system_info SET value = value; ROLLBACK; assert no 25006 (a 0-row UPDATE still trips read-only, and ROLLBACK keeps the box byte-identical; do NOT use a TEMP table — temp writes are ALLOWED under read-only and would be illusory). The write probe proves the operator-visible truth (box accepts writes) regardless of which mechanism delivered it; the journal negative proves it was the RIGHT mechanism. So the answer to the open question is both-and: fixed transport-real assert_health_passes (must-fix 2) + backstop-silence journal assert + write-probe belt. A structural pin alone was never enough — arcs prove what must run.

MINOR 4 — COMMENT TRUTH ON THE WINDOW FLIP. The new comment says 'the completed UPDATE landed above (senior truth)' — but on the scanErr!=nil branch it did NOT land, and the flip still runs. The BEHAVIOR is approved: this function's contract is continue-to-cleanup (:3040-3042), the completed-write invariant already escalated loudly, the box is serving, and the tick belt (:2312) retries the completed write next pass — holding an NSO's registry read-only over a bookkeeping write failure would be the wrong trade. But the comment must state the divergence from applyNewSbUpgrading's return-on-failure (:6168) and why it is deliberate, not claim the write landed.

MINOR 5 — PIN THE 192 FLIP SITE IN THE STRUCTURAL TEST. read_only_window_flip_test's floor of ≥2 pins nothing new: the PRE-diff source already had three terminalExec(windowOffSQL) sites (backstop :3557, completion :6213, rollback :7524). Add a contains-assert on the 192-specific escalation narrative ('flagless-recovery completion') so the new site cannot silently drop out of a future refactor.

OBSERVATION (pre-existing, NOT this diff's scope — foreman may want a backlog entry): resumeNewSb's self-heal branch (:6668-6737) can complete a PARKED row — its UPDATE guards on state='in_progress' only, and a parked row IS in_progress, so a parked box that later finds itself serving at target (containers up, no pending, health passes) completes without a deliberate un-park. Outcome-wise this satisfies the 160 doctrine (completed-only-when-serving) but contradicts 'a parked row un-parks ONLY via a deliberate operator trigger' as written on the 135 guard. Pre-dates this diff; the parked state THIS fix creates has containers down, so the branch cannot fire on it immediately. Flagging, not expanding scope.

PROCESS: amendments 1-5 are engineer work on the same frozen unit; when they land I do a DELTA re-review of the amended hunks only, then the commit → AC#3 RED run (pre-fix HEAD) → GREEN run (the commit). The RED run must now fail at the FIXED assert_health_passes (502 on a dark box), not at the old illusory 200.
---

author: architect
created: 2026-07-18 13:43
---
AC#4 DELTA RE-REVIEW (architect, 2026-07-18) — verdict: SHIP. All five amendments verified in the bytes, not from the report. AC#4 checked.

1. Watchdog cover: byte-mirrors :5874 (gated ticker, appendLog progress, same stall/cadence constants), gate-open bump on entry, cancel+join via one deferred closure. Defer ordering verified LIFO-correct: ticker joins FIRST, then the progress log closes, then the parkedExit-guarded flag cleanup runs last — no use-after-close, no ping past return. Ticker scope extends past healthCheck through the completed write + flip — broader than my minimum, harmless (gate stays open ≤3m past the last Write; terminal writes are bounded). watchdog.go doc note updated to four callers.
2. Health probe: Host header + domain resolution (env → VM .env.config → statbus-test.local default, matching vm-bootstrap:270). The probe now traverses http://{{.Domain}} → handle @rest → reverse_proxy rest:3000; dark box → 502 → RED.
3. Arc discriminator: negative journal assert on 'STATBUS-163 BACKSTOP' (arm-scoped SINCE) + write-probe belt (BEGIN; UPDATE public.system_info SET value=value; ROLLBACK — the dropped WHERE clause vs my example is fine: all-rows-rolled-back is still byte-identical, and even an empty table trips read-only at the executor; temp-table trap correctly avoided).
4. Window-flip comment now states the flip runs regardless of the completed-write outcome and names the deliberate divergence from :6168. Truthful.
5. Flip test pins the 192 site via its unique escalation narrative.

ACCEPTED RESIDUALS (recorded, no further iteration): (a) journal_has returns 'no' on a journalctl/ssh failure too, so the negative backstop assert could vacuously pass on a transport blip — narrow double-fault corner (blip AND backstop-fired AND lift-failed), partially covered by the write-probe belt; the run oracle + failure diagnostics dump would surface it on any later red. (b) The write probe's grep can't distinguish 'DB unreachable' from 'no 25006' — acceptable because the arc proved the DB reachable moments earlier (row-state polling).

INDEPENDENT VERIFY (not the engineer's report): go build ./... clean, go vet clean, go test ./internal/upgrade -count=1 PASS (12.7s), bash -n clean on the arc + assertions.sh.

GREEN LIGHT: foreman commits the frozen 6-file unit. Then AC#3: RED run on pre-fix HEAD — expected failure point is the FIXED assert_health_passes (502 on the dark box; if it instead fails elsewhere or passes, STOP and bring it back, no assert loosening); GREEN run on the commit — expected full pass including backstop-silence + write probe. The run is the oracle; PROVEN only on an explained green.
---

author: foreman
created: 2026-07-18 13:44
---
COMMITTED (7f690fb22, pushed to master) on the architect's delta re-review SHIP verdict (comment #5, AC#4 checked). The 6-file unit: service.go (serve-proven tail: disk precheck → compose up → app health gate → maintenance off → completed write → window lift with loud escalation, all under the gated watchdog ticker; health-fail → faithful-flag-then-park with parkedExit-guarded defer; compose-up failure → existing three-way; parked-skip guard first, untouched), watchdog.go (four-callers doc note), the two re-anchored structural tests, the arc (assert_health_passes + negative journal assert on the STATBUS-163 backstop marker + real-table write-probe belt), assertions.sh (Host: <SITE_DOMAIN> — deliberate fleet-wide strictness increase; illusory greens elsewhere may now fail, which is the gate working). REMAINING: AC#3 VM oracle — RED run on pre-fix product (must fail AT the fixed assert_health_passes with 502 on the dark box; failing anywhere else or passing → STOP, back to the architect, no assert loosening) and GREEN run on 7f690fb22 (everything passes incl. backstop-silence + write probe; PROVEN only on an explained green). Runs dispatched to the engineer.
---
<!-- COMMENTS:END -->
