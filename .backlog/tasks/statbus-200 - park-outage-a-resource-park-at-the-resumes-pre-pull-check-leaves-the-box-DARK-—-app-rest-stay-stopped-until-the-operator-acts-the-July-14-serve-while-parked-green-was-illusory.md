---
id: STATBUS-200
title: >-
  park-outage: a resource park at the resume's pre-pull check leaves the box
  DARK — app/rest stay stopped until the operator acts; the July-14
  serve-while-parked green was illusory
status: In Progress
assignee:
  - '@engineer'
created_date: '2026-08-02 19:10'
updated_date: '2026-08-16 17:55'
labels:
  - upgrade
  - recovery
  - defect
  - park
dependencies: []
references:
  - cli/internal/upgrade/service.go
  - test/install-recovery/arcs/un-park-to-completion-arc.sh
  - test/install-recovery/lib/assertions.sh
priority: medium
ordinal: 200000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
> NORTH STAR: a parked box is alive-idle AND operable — the operator's remedy lever (the web UI) must be up while the box awaits the deliberate un-park; a park must never be a silent outage.
> FOUND: 2026-08-02, architect triage of arc run 30755799405 (un-park-to-completion RED). PRE-EXISTING defect, NOT a regression of cut candidate 2ab6126a1 — newly UNMASKED by two honesty fixes.
> STAGE: disposition ruled by the architect below; fix design needs the King's nod before staging.

THE DEFECT (byte-walked): a NO-DELTA upgrade claims → executeUpgrade stops app services pre-swap → binary swap → exit-42 handoff → the resumed binary's pre-pull disk check (diskPrecheckReason(StepImagePull), service.go:5946) PARKS on the disk floor. The park is correct (named reason, one siren, alive-idle daemon, no rollback) — but app/rest/worker were stopped by the pre-swap pipeline and NOTHING restarts them: the box serves 502 (proxy up, upstreams down) until the operator frees the disk and re-triggers. The same class applies to every pre-start park site (StepImagePull :5946, StepStartServices :3123/:6218).

WHY IT LOOKED GREEN ON 2026-07-14 (run 29367295181): the harness health probe then sent NO Host header, and Caddy's implicit answer for an unmatched request was HTTP 200 with an EMPTY body — an illusory pass on a dark box. STATBUS-192 must-fix 2 (7f690fb22, 2026-07-18) hardened the probe to send Host (assertions.sh:16-38 documents the mechanism verbatim); STATBUS-189 (337cb48e9) closed the implicit-200 hole itself with an explicit :80→404. Run 30755799405 was this arc's first run with the honest probe — 60×502 over 5 minutes with docker ps showing only db+proxy up. The arc file is byte-unchanged since its green (e9b3d3bb0); its own premise comment ("the pull never ran, the OLD version keeps serving") records the intended contract.

DISPOSITION (architect, 2026-08-02): the contract is right and the product is wrong. In the operator frame the web UI is the only remedy lever — a park that takes it down mutes the box (the loops-forever-while-nobody-is-told genre, softened only by the one siren). FIX SHAPE for the King's nod: before going alive-idle, the park path restores the SOURCE version's services — the old images are local (no pull, no disk pressure beyond what exists), docker compose up + bounded health wait, maintenance mode OFF and the read-only window LIFTED only if the source version verifiably serves (the serve-proven discipline applied to the park's service restoration; if the restore itself fails, park anyway — alive-idle daemon — with the reason narrative extended, never a crash loop). Alternative REJECTED: re-ruling the contract to "parked = dark box behind a maintenance page" — it contradicts the arc's ratified premise and the operator frame.

ORACLE: the un-park-to-completion arc, unchanged — its honest probe now demands exactly this contract; green on a real VM is the proof. Plus a Go unit on the park path's restore-before-idle ordering.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 A resource park at any pre-start step leaves the SOURCE version serving (web UI + rest up, data intact) while the row is parked; the read-only window and maintenance mode reflect the ruled contract
- [ ] #2 The un-park-to-completion arc is green on a real VM with the honest Host-carrying probe — no arc changes
- [ ] #3 If the service restoration itself fails, the box still parks alive-idle with the failure folded into the park narrative — never a crash loop, never a silent success claim
- [ ] #4 The restoration is ERA-GUARDED: source services start only when the DB carries no applied delta from this attempt (pending set unchanged — the no-delta and pre-delta cases); a park with the delta applied never starts source containers against a migrated DB; the guard's refusal is named in the park narrative
<!-- AC:END -->

## Comments

<!-- COMMENTS:BEGIN -->
author: architect
created: 2026-08-16 14:05
---
KING'S NOD RECEIVED (2026-08-16, his console, verbatim: 'Don't delay, do the park fix.') — build authorized, jumps to the front of the engineer's queue. BUILD SPEC PRECISION (architect, appended so the brief is whispers-proof):

1. WHERE: the pre-start park sites — diskPrecheckReason(StepImagePull) at service.go:5946 and the StepStartServices sites (:3123, :6218) — plus the disk-full in-flight parks (:3137, :5953). Before the alive-idle settle (after the park write lands — the park itself must never be blocked by the restoration), the daemon attempts to bring the SOURCE version's services back: docker compose up with the LOCAL source images (no pull — that is the whole point; the disk is full), bounded health wait, then maintenance OFF + read-only window LIFT only on a passing health gate (serve-proven discipline applied to the restoration — never claim serving without proving it).

2. THE ERA GUARD (the safety core of this fix): restore ONLY when the DB carries no applied delta from this attempt — the no-delta (codeonly) case and any pre-delta park. If the delta (or part of it) has applied, source containers against a migrated DB are the mixed-era class — do NOT start them; keep the maintenance page, fold 'services held down: migration delta applied, source version incompatible' into the park narrative. The existing pending-migrations read the self-heal already uses (resumeNewSb's no-pending check) is the reuse point for this verdict.

3. FAILURE OF THE RESTORATION ITSELF: park anyway, alive-idle, with the restoration failure appended to the park narrative (the one atomic parkUpgrade write already carries error narrative — extend the reason text, never a second write channel). Never a crash loop, never a silent success claim, and the maintenance page (proxy) remains the honest face.

4. ORDERING PIN: park write FIRST, restoration attempt SECOND — a crash mid-restoration must leave a parked row (the parked-skip invariant then holds on the next boot; a restoration crash must not consume attempts or strip the flag).

ORACLES: (i) the un-park-to-completion arc UNCHANGED — its honest Host-carrying probe demands exactly the restored-and-serving contract; green on a real VM is the proof (AC#2); (ii) Go unit: pre-start park with no delta → restoration invoked after the park write, window lifted only on health pass; (iii) Go unit: delta-applied park → restoration refused with the named narrative (the era guard, AC#4); (iv) Go unit: restoration failure → row parked, narrative extended, no crash (AC#3). Sequencing: service.go collides with 197 — strictly sequential on the engineer's lane, 200 FIRST per the King's word; 197 follows.
---

author: foreman
created: 2026-08-16 14:05
---
KING AUTHORIZED (2026-08-16, via the architect's console): 'Don't delay, do the park fix.' Moves to In Progress ahead of 197 on the engineer's lane — both touch service.go, strictly sequential, 200 first (197 dispatches after 200 lands). Build brief is comment #1 (whispers-proof, four spec points: pre-start-site restoration with LOCAL source images; the ERA GUARD as the safety core — restore only when no migration delta applied, AC#4; restoration-failure folds into the one atomic park narrative; ordering pin — park write FIRST so a mid-restoration crash still leaves a parked row). Oracle: the unchanged un-park arc on a real VM. Engineer proceeds to this directly after freezing 201; architect frozen-diff review (safety core), foreman commits.
---

author: foreman
created: 2026-08-16 14:18
---
BUILD HELD — BRIEF DEFECT FOUND IN THE SAFETY CORE (engineer byte-walk, 2026-08-16; four rulings pending with the architect): comment #1's named era-guard reuse point (resumeNewSb's HasPending) produces the WRONG verdict in two of three cases — a PRE-delta park (e.g. disk-full at StepImagePull :5946, before migrate at :6135) has HasPending=TRUE with the DB still pure source (must permit; bare check wrongly refuses), and a POST-delta park (StepStartServices :6230, after migrate) has HasPending=FALSE with the delta applied (must refuse; bare check wrongly PERMITS — the mixed-era corruption the guard exists to stop). Open rulings: Q1 how 'no applied delta' is computed (baseline-max-at-claim vs source-expected-max comparison); Q2 restoration mechanic = rollback restore tail MINUS restoreDatabase (git+binary+config to source first — target images were never pulled, so compose-up-local from the target tree cannot work); Q3 restoration-failure narrative needs a SANCTIONED second write to the already-parked row (guard recovery_parked_at IS NOT NULL) vs journal-only; Q4 whether completeInProgressUpgrade's AT-TARGET parkAtTarget sites (:3123/:3137) are in scope — 'restore source' doesn't apply at target. Engineer's three RED-first Go units stand ready; build resumes on the rulings.
---

author: architect
created: 2026-08-16 14:23
---
FOUR RULINGS on the engineer's hold (architect, 2026-08-16). First: the hold was exactly right and the brief's comment-#1 point 2 was WRONG — 'permit iff !HasPending' fails two of his three cases (pre-delta park: pending=true but DB pure source → must permit; post-delta park: pending=false with delta applied → must refuse). The reuse point is withdrawn; credit to the engineer for refusing to build a corrupting guard.

Q1 — THE VERDICT IS A SOURCE-IDENTITY COMPARISON, NOT A PENDING CHECK. Permit iff the DB's applied migration max EQUALS the SOURCE version's expected max, computed from already-recorded identity: resolve the row's from_commit (recorded at claim; short sha → git rev-parse) and read the source tree's migration set locally via git ls-tree <source-sha> -- migrations/ (filename-parse the versions; no checkout — works while the tree sits at target). db_max == source_max → PERMIT (DB is provably at source: covers codeonly AND pre-delta). db_max > source_max → REFUSE (delta partially or fully applied — the mixed-era class). db_max < source_max, source sha unresolvable, ls-tree failure, or DB unreadable after the recovery-start attempt → REFUSE with the anomaly named (fail-safe direction is ALWAYS refuse: a dark box behind the maintenance page is safe; serving mixed-era is not). REJECTED: HasPending (proven wrong); pre-migrate baseline capture (new persisted state + capture-timing risk across resume attempts, where the identity comparison uses facts already recorded and directly encodes the invariant 'the DB is at the source version's state'). DB may be down at park time: bring it up via the existing recovery machinery (EnsureDBReachable/StartDBForRecovery) BEFORE the read — a running DB under the still-engaged read-only window is harmless.

Q2 — RESTORATION MECHANICS CONFIRMED as proposed: the rollback restore tail MINUS restoreDatabase — restoreGitState(pin) + restoreBinary(sb.old) + config-generate (source tag → source images are local) + compose up --no-build + bounded health; maintenance OFF + window LIFT only on health pass. Two riders: (i) run it unconditionally on permit — both restores are idempotent no-ops when nothing moved (checkout -f onto current HEAD; restoreBinary silently no-ops without sb.old), so pre-checkout parks need no special case; (ii) the 197 boundary stated plainly: this path runs only in attempts that got past backup (their pin and sb.old are their OWN — identity holds); the never-ran class (empty backupPath) is 197's guard and the two never collide.

Q3 — (a) SANCTIONED, as a NARRATIVE-ONLY operation: appendParkNarrative — a teardown-immune UPDATE that APPENDS to the parked reason/error, guarded `recovery_parked_at IS NOT NULL AND state='in_progress'`, and by construction never touches recovery_parked_at, never consumes attempts, never flips state. Single caller, pinned by unit. The 154/193 single-park-writer discipline is preserved — parkUpgrade remains the only site setting recovery_parked_at (the 196 drift gate's SingleParkWriter pin keys on `recovery_parked_at = now()` and is untouched).

Q4 — IN SCOPE BY UNIFICATION, no site map judgment: ONE shared helper (parkServiceRecovery) called after the park write at ALL THREE sites; the Q1 guard computes the verdict, so at-target parks (completeInProgressUpgrade's parkAtTarget, and post-delta StepStartServices) refuse NATURALLY with the named narrative — no site-local special cases. Hard rule for the helper: it only ever STARTS services on permit; on refuse it stops NOTHING and changes nothing but the narrative (the health-park arcs' at-target parks keep their running-but-unhealthy services exactly as today).

ORACLES, RED-first, per the engineer's set plus: pre-delta permit, post-delta refuse, codeonly permit, identity-unresolvable refuse, narrative-append single-caller pin, helper-never-stops pin. The un-park arc unchanged remains the VM proof.
---

author: foreman
created: 2026-08-16 14:42
---
BUILT + FROZEN, foreman-verified (2026-08-16; architect frozen-diff review queued behind the cut window). Two files: service.go + park_service_recovery_test.go. All four rulings realized: single chokepoint (parkAtTarget delegates through parkForDeterministicFailure — one parkServiceRecovery call after the park write covers all three sites, idempotent so a next-boot re-entry completes a crash-interrupted restore); SOURCE-IDENTITY era guard (db_max via the teardown-immune read — no queryConn dependency at the pre-reconnect park — vs the source sha's migration max via git ls-tree, NO checkout; permit iff equal, every anomaly REFUSES toward dark-behind-maintenance); restore = rollback tail minus restoreDatabase, window lifted only after health; appendParkNarrative narrative-only under recovery_parked_at IS NOT NULL, never assigns the timestamp — parkUpgrade stays sole writer, 196 gate green with token count exactly 1. Foreman re-ran: package build+vet, all three RED-first oracles PASS (the era unit would have gone RED on the withdrawn HasPending design), drift gate PASS. Honest flags recorded: pre-existing env-dependent DB-integration test failure (missing generated test .env — routes to the tester); AC#2's VM proof (unchanged un-park arc, honest probe) rides the post-commit dispatch. Commit follows architect review after the cut window.
---

author: foreman
created: 2026-08-16 17:55
---
COMMITTED b47a2bce9 (foreman, 2026-08-16; architect approved from the freeze snapshot, cut window closed with byte-identical restore first). AC#1/#3/#4's code side is landed: the chokepoint helper after every park write, the source-identity era guard refusing every anomaly toward dark-behind-maintenance, the narrative-only failure append, the idempotent re-entry. TICKET STAYS OPEN on its run oracle: AC#2 — the UNCHANGED un-park-to-completion arc green on a real VM with the honest probe — rides the next arc-suite dispatch (the King's cut tag, or the manual dispatch that follows it). The architect's one review finding is filed as STATBUS-204 (the two budget-park sites still bypass the helper — same class, rarer trigger; queued after 197); his non-blocking naming note (terminalUpdate used for SELECTs → a later rename like terminalQueryRow) rides any future pass. 197 dispatches to the engineer now on the freed service.go baseline.
---
<!-- COMMENTS:END -->
