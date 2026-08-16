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
updated_date: '2026-08-16 14:18'
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
<!-- COMMENTS:END -->
