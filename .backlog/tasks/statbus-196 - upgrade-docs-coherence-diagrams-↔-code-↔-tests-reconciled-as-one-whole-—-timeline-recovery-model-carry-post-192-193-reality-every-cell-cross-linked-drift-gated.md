---
id: STATBUS-196
title: >-
  upgrade-docs-coherence: diagrams ↔ code ↔ tests reconciled as one whole —
  timeline + recovery-model carry post-192/193 reality, every cell cross-linked,
  drift gated
status: In Progress
assignee:
  - architect
created_date: '2026-07-25 19:21'
updated_date: '2026-07-29 16:01'
labels:
  - upgrade
  - install-recovery
  - documentation
  - coherence
dependencies: []
references:
  - doc/upgrade-timeline.md
  - doc/upgrade-recovery-model.md
  - test/install-recovery/arcs/
  - .backlog/tasks/statbus-071
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
> NORTH STAR (King, 2026-07-23): the upgrade diagrams, the code, and the tests are one coherent whole. The diagrams cover everything that needs covering. One place states what went wrong on Rune. Everything 071 claims is covered by a scenario. Nothing drifts.

THE PROBLEM TODAY (probe-verified 2026-07-25):
- doc/upgrade-timeline.md does not mention the park lifecycle or the serve-proven completed contract. It predates both. (It already carries the completed-label trio, incl. [completed-self-heal], at :213.)
- doc/upgrade-recovery-model.md predates 192 (completed = verifiably serves, at every writer), 193 (the self-heal parked guard), and 195 (the discovery watchdog false-kill).
- The 071 coverage map is current. The drift is in the prose diagrams, not the map.

THE WORK, five steps:
1. TIMELINE. Add the park lifecycle (park → alive-idle → un-park by the operator, or displacement by a fix release) and the serve-proven completed contract. One pass. Architect reviews.
2. RECOVERY MODEL. Add the parked-skip invariant (every automatic resume skips a parked row — 135, 193) and the watchdog-cover principle (195: the watchdog kills hung daemons, never slow-but-live ones).
3. CROSS-LINK, both ways. Every diagram element names its covering arc or scenario — or says "uncovered", plainly. Every arc and scenario names its diagram element. The 071 map is the join table; reference it, or move its durable content into the docs.
4. THE RUNE STATEMENT. One named place in the recovery model says what went wrong on Rune, in two layers: the extinct wedge (root cause fixed — e76505eec skips --now in the fixup during an active upgrade; 61e79e265 lands the terminal UPDATE before the fixup, so the window no longer exists; cb7344dd6 adds the self-heal net) and the live class — a box that loops forever while nobody is told (covered by the budget/park arcs, the restart-bound asserts, and the 069 canary).
5. THE DRIFT GATE. A structural check that fails loudly when a new terminal state, park writer, or recovery dispatch arm lands in cli/internal/upgrade without its diagram line. The gate watches the visible artifact: the doc diff.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 The timeline carries the park lifecycle and the serve-proven completed contract; architect-reviewed
- [x] #2 The recovery model carries the parked-skip invariant and the watchdog-cover principle
- [x] #3 Cross-links stand in both directions; "uncovered" is stated, never implied
- [x] #4 The Rune two-layer statement stands in the recovery model with its fix citations
- [ ] #5 The drift gate exists and a probe proves it fires
<!-- AC:END -->

## Comments

<!-- COMMENTS:BEGIN -->
created: 2026-07-29 11:14
---
GROUNDING RECONCILED (architect, 2026-07-29; operator legwork at tmp/agents/operator-196-142-legwork.md + my term-count verification — two partial records, one truth from the bytes):

TERM COUNTS, verified today: upgrade-timeline.md (last touch 07-14): parked 0, serve-proven 0, read-only-window 0 — but self-heal 7, boot-migrate 3. upgrade-recovery-model.md (07-12): parked 3, read-only-window 3 — but serve-proven 0, self-heal 0. So: the TIMELINE is the big gap exactly as drift-flagged (the park lifecycle, the serve-proven contract, and the window are entirely absent from the operator-facing lifecycle doc); the MODEL is NOT park-blind — it carries park + window and needs UPDATING to post-192/193/195 reality (serve-proven at every writer; the self-heal named inside the decision rules with its 193 parked-guard; the 195 watchdog-cover principle), not fresh authoring. My earlier 'both docs lack park' was overbroad; the operator's 'coherent and current' was too generous on the timeline — the counts are the record.

INVENTORY for step 3's cross-links: 30 real-path arcs + 15 scenarios, each with its one-line purpose, listed in the operator's file — the join-table raw material is gathered; the coverage-map on 071 remains the run-ledger side.

EXECUTION: I write the two doc passes myself (architect-lane — doctrine-heavy, the King's register), one doc per unit, foreman line-reviews + commits each; then the cross-links, the Rune statement, and the drift gate per the description's steps 3-5.
---

author: architect
created: 2026-07-29 11:20
---
UNIT 1 BUILT — THE TIMELINE PASS (architect, 2026-07-29; frozen for foreman line review + commit; one file, doc/upgrade-timeline.md, +125/-61). What the pass found went well beyond the flagged terms — the prose carried THREE eras of drift, all fixed:

1. AC#1 CONTENT, as planned: the PARK LIFECYCLE (a full tier under the renamed 'Complete / rollback / park' section — what parks, the atomic park write, one siren, alive-idle, flag kept, every-resume-skips, the two deliberate exits) + the parked-marker note after the state table (orthogonal to state; a deploy terminal for CI; why 159's displacement exists) + the SERVE-PROVEN completed contract at step 13 naming all three writers + the read-only window (engage at step 3, lift inside serve-proven completion, data-safety rationale).

2. FOUND DRIFT, fixed because a truthful doc can't carry it next to new content: (a) PRE-145 INVERSION — the prose claimed boot-migrate 'applies every upgrade's migration delta' and step 11 is 'normally a no-op'; reality is exactly opposite (floor-bounded boot, delta exactly once in the guarded step 11) — rewritten in both places; (b) PRE-164 NAMES — resumePostSwap/applyPostSwap/Phase=PostSwap/Resuming throughout → resumeNewSb/applyNewSbUpgrading/new-sb-swapped with the legacy-alias note; grep-zero stale refs now; (c) PRE-046 RETRY-FOREVER — the decision tree said an at-target box 'keeps failing forward, stays loud' unboundedly → now the attempt budget, first-occurrence deterministic park, same-step-twice, budget exhaustion; (d) added 144's flagless alive-idle guard + 195's discovery heartbeat to Service boot; (e) the two-row model names all three completed writers as serve-proven; (f) the renamed section's anchors updated everywhere.

3. INVERTED-DRIFT FINDING for step 3's cross-link work: the lifecycle DIAGRAM SOURCE (upgrade-lifecycle.plantuml:42-45) ALREADY carries the park — the diagrams were updated when 046 shipped; only the prose drifted. Step 3 verifies diagram completeness properly, but the assumed diagram-gap is smaller than feared.

AC#1 checks after the foreman's line review + commit. Unit 2 (the recovery-model pass) follows.
---

author: foreman
created: 2026-07-29 11:21
---
UNIT 1 (timeline pass) REVIEWED + COMMITTED 8cc4cca1c (foreman, 2026-07-29). Line review verified every load-bearing claim against code symbols, not prose: DaemonSchemaFloor exists at the boot site (145 floor-bound confirmed — service.go + daemon_floor_bootsite_test.go); PhaseNewSbSwapped='new-sb-swapped' with the post_swap/resuming legacy-alias map at service.go:253-301; resumeNewSb/applyNewSbUpgrading/newSbUpgradingFailure all exist (service.go:5718/5844/6773) and the OLD names are grep-zero in code AND in the doc; PriorDeathStep same-step-twice seam real (recovery_escalation.go:151); read-only window real (exec.go:351-366). Anchor check: zero references to the old #complete--rollback anchor repo-wide, 3 internal refs to the new #complete--rollback--park, heading present, no cross-doc links to the renamed section. AC#1 checked. The inverted-drift finding (lifecycle plantuml already carries the park) is noted for step 3's smaller diagram gap. Unit 2 (recovery-model pass) may proceed.
---

author: architect
created: 2026-07-29 11:29
---
UNIT 2 BUILT — THE RECOVERY-MODEL PASS, carrying steps 2 AND 4 in one frozen diff (architect, 2026-07-29; doc/upgrade-recovery-model.md, +16/-4). Both steps edit the SAME file, so I merged them into one review unit — one foreman line-review instead of two on the same bytes. Five touch points, every claim verified against code or git before writing:

1. AC#2a PARKED-SKIP INVARIANT: the §4 parked entry now names all three enforcement sites — the flagless heal's skip-before-the-defer-arms (completeInProgressUpgrade, 135), the budget section's skip-without-consuming-an-attempt (046), and the self-heal's primary read + atomic `recovery_parked_at IS NULL` write guard (193, the lone-exception closure). Closing line: no automatic path can complete a parked row, strip its flag, or consume one of its attempts.

2. AC#2b WATCHDOG-COVER PRINCIPLE: new third bullet under §What enables it — the watchdog kills hung daemons, never slow-but-live ones; every long-running main-goroutine loop feeds it per unit of genuine progress (idle ticker, executeUpgrade progress writes, boot-migrate ticker, discovery per-candidate — the 195 false-kill, run 29743621767, cited from the a316b1a2b commit message). Per-unit heartbeats keep hang detection by construction: stuck-on-ONE-unit still starves it.

3. AC#4 THE RUNE STATEMENT: new named section 'What actually went wrong on Rune (the 18-day hang, in two layers)'. Layer 1 extinct wedge with the three fix citations — all three SHAs verified in git log today (61e79e265 terminal-UPDATE-before-fixup, e76505eec skip --now inside active upgrade, cb7344dd6 self-heal net). Layer 2 the live loops-forever-while-nobody-is-told class, held down by budget/park + the harness NRestarts asserts + the 069 canary. The §window bullet's '18-day rune hang' mention now cross-references the section.

4. SERVE-PROVEN at §4 completed (the drift the grounding comment flagged): completed = verifiably serves at EVERY writer; all three writers named with their tickets (192 flagless heal; 071 P5 self-heal tail — verified via commit 2616d02ea as the commit that added the self-heal's window lift); health-fail at target → park, never a completed lie.

5. STATUS refresh: re-verified date → 2026-07-29; three new SHIPPED lines (serve-proven 160/192 with the window-flip + guarded-defer pins; 193 parked-guard with TestResumeNewSb_SelfHealSkipsParkedRow + the postswap-converged-selfheal arc; 195 with TestVerifyArtifacts_FeedsWatchdogPerCandidate) — all pin names verified present in recovery_escalation_test.go / read_only_window_flip_test.go today.

Stale-name sweep: resumePostSwap/applyPostSwap/Phase=PostSwap grep-zero in the doc. FROZEN for foreman line review + commit; AC#2 and AC#4 check together on that commit. Next: unit 3 (cross-links, using the operator's 30-arc/15-scenario inventory) and unit 5 (drift gate).
---

author: foreman
created: 2026-07-29 11:32
---
UNIT 2 (recovery-model pass) REVIEWED + COMMITTED 4ea57df17 (foreman, 2026-07-29). Citation-verified before commit: all three Rune fix SHAs (61e79e265 / e76505eec / cb7344dd6) resolve in git with good signatures; the parked-guard SQL (`recovery_parked_at IS NULL`) at service.go:6690 with its guard rationale at :6659-6663; completeInProgressUpgrade at service.go:2869; both cited pin tests exist (recovery_escalation_test.go, read_only_window_flip_test.go) and were green in today's full upgrade-package run; WatchdogSec=120 confirmed in ops/statbus-upgrade.service, 30s cadence constants in watchdog.go/service.go. Acceptance criteria 2 and 4 checked — the architect's merge of both steps into one unit was right (same file, same bytes, one review). Remaining: step 3 (cross-links both ways) and step 5 (drift gate) → acceptance criteria 3 and 5.
---

author: architect
created: 2026-07-29 15:59
---
UNIT 3 BUILT — CROSS-LINKS BOTH WAYS (architect, 2026-07-29; FROZEN for foreman line review + commit). Five files: doc/diagrams/upgrade-timeline.plantuml, upgrade-lifecycle.plantuml, install-recovery.plantuml, doc/upgrade-timeline.md, test/install-recovery/README.md. Every claim below verified against the FILES today (arcs dir: 31 files, not the 30 previously reported; scenarios: 15).

DIRECTION diagram→test (the in-diagram TEST notes, refreshed to current truth):
1. upgrade-timeline.plantuml's notes were a full era stale — they cited 10+ scenario slugs DELETED in the U5 sweep (2-preswap-*, 4-rollback-kill, 3-postswap-mid-*/between-*/migration-*, resume-died-parked). All now name the covering arcs. The giant resume-died-parked historical narrative is replaced by the current park coverage (postswap-health-park-arc, un-park-to-completion-arc, recovery_escalation_test.go logic-pins).
2. TWO in-diagram drifts corrected beyond slugs: (a) the note claimed the commit↔record cells fire at BOOT-MIGRATE — pre-145, contradicting the same file's own :124-134; now: all cells fire at the applyPostSwap delta site, with THE RULED RULE stated (pre-delta death → forward → completed; mid-delta with ledger advanced → Behind → one-shot rollback). (b) the between-migrations cell claimed 'completed' — the proving run 28976918080 says rolled_back; corrected. The pre-145 kill-during-migration INVARIANT note rewritten to the atomicity flip.
3. New TEST lines where coverage existed but was unnamed: schedule band (claim-without-notify-arc, deploy-status-proof-arc), boot band (flagless-selfheal-at-target-arc, boot-migrate-churn-alive-idle-arc), rollback band (restore-watchdog, pair-terminal, restore-broke-reattempt, transient-db-backoff, c-rollback-resurrection), postswap tail (converged-selfheal, cross-version-rename-handoff).
4. Gaps kept honest and now ticketed: the preflight claim-window kill gap cites STATBUS-197 (ruled; fix design pending) in both the boot-belt and preflight notes; takeover arm, StateHalfConfigured, StateDBUnreachable, legacy-refuse, inline-dispatch, [HUMAN: unknown] self-loop, skipped/dismissed all stay NO TEST / UNCOVERED, stated plainly.
---

author: architect
created: 2026-07-29 16:00
---
UNIT 3, second half of the record (architect, 2026-07-29):

DIRECTION test→diagram: NEW section in test/install-recovery/README.md — 'Coverage join table — every test names its diagram element'. All 31 arcs + all 15 scenarios mapped to their diagram element (the sequence diagram's == bands, the state diagram's transitions, the activity diagram's partitions/arms), closing footnote listing every uncovered element by name. The join carries ELEMENT MAPPING only; run-proof stays on 071's map (runs change, the element mapping doesn't — smaller drift surface).

MORE DRIFT FIXED EN ROUTE (all file-verified): (a) doc/upgrade-timeline.md said '8-state probe ladder' in two places and its ladder table had 8 rows — state.go has NINE; StateRestoreReattemptable was missing entirely; row added with its proving arc, rows renumbered. (b) The ladder's crashed-upgrade row cited a stale scenario ref ('08') — replaced with the real provers (kill-family recovery dispatches + the two STATBUS-143 proxy arcs). (c) The upgrade-lifecycle diagram had NO coverage notes at all — new TESTCOV note maps every transition, UNCOVERED stated for the [HUMAN: unknown] self-loop and the skipped/dismissed acknowledgement paths. (d) README catalogue heading said 19 scenarios; 15 files exist — fixed. (e) README's 4-flagless-selfheal-at-target row claimed the scenario exists as an interim net [UNPROVEN] — the file was deleted in 86c626ab0 after its real-path successor arc went green (run 29400318076); row rewritten as RETIRED with the citations. (f) The add-a-scenario checklist now requires a join-table row for new tests.

FOUND FOR THE RECORD, needs no action now: 071's coverage map cites postswap-archivebackup-watchdog-arc as [PROVEN], but no such file exists — the archiveBackup feature was removed in STATBUS-112 and the arc went with it. One stale map row; the join was built from the FILES, which are the record.

VERIFICATION: plantuml -checkonly green on all three sources; stale-slug sweep grep-zero across the three diagrams + both docs; the anchors in the new cross-references resolve; SVGs regenerate via the .githooks/pre-commit hook when the foreman stages the .plantuml files (no manual step). AC#3 checks on the foreman's commit. NEXT: unit 5, the drift gate (design first, probe must prove it fires).
---

author: foreman
created: 2026-07-29 16:01
---
UNIT 3 (cross-links both ways) REVIEWED + COMMITTED c95e7de4a (foreman, 2026-07-29; 8 files — the five sources plus the three hook-regenerated SVGs). Independent verification before commit: plantuml -checkonly green on all three sources (re-run myself); the 9-state ladder matches cli/internal/install/state.go exactly (StateRestoreReattemptable present at :51, ladder position 8, populated fields at :95-96); all six newly cited arc slugs exist on disk (postswap-stopped/severed-proxy, claim-without-notify, restore-broke-reattempt, preswap-backup-kill, flagless-selfheal-at-target); retired scenario slugs grep-zero in the diagram sources; the join table's 31-arc count matches the arcs/ directory exactly. Acceptance criterion 3 checked — both directions stand and every gap is stated plainly (the state-2 takeover arm, states 4/5/6, the state-7 inline path). Remaining on this ticket: step 5 only (the drift gate, criterion 5). The architect's 071-ledger finding (map cites postswap-archivebackup-watchdog-arc [PROVEN] but the arc died with STATBUS-112's archiveBackup removal — verified: zero matching files in arcs/) is recorded on STATBUS-071 same-turn so it survives as a durable note.
---
<!-- COMMENTS:END -->
