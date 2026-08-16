---
id: STATBUS-200
title: >-
  park-outage: a resource park at the resume's pre-pull check leaves the box
  DARK — app/rest stay stopped until the operator acts; the July-14
  serve-while-parked green was illusory
status: To Do
assignee: []
created_date: '2026-08-02 19:10'
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
<!-- AC:END -->
