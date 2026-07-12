---
id: STATBUS-107
title: >-
  plain-upgrade-language: de-jargon the upgrade/recovery vocabulary — "booting
  the new binary", one by one
status: Done
assignee: []
created_date: '2026-06-21 19:41'
updated_date: '2026-07-12 14:21'
labels:
  - upgrade
  - recovery
  - docs
  - clarity
  - de-jargon
dependencies: []
references:
  - doc/upgrade-timeline.md
  - doc/recovery/
  - cli/internal/upgrade/service.go
  - doc/upgrade-vocabulary.md
ordinal: 107000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
> NORTH STAR: the most safety-critical code we own reads in plain language — understood without a glossary.
> BENEFIT: reviewers and operators stop misreading the recovery model at the worst moment; every future review of upgrade code gets cheaper and safer because the words match the mechanics.
> STAGE: Stage 1 (clarity lane; doc/upgrade-vocabulary.md is the registry).
> COMPLEXITY: mixed — architect locks the remaining vocabulary (mechanisms & artifacts); mechanic applies the 3-diagram de-jargon; engineer does the code identifier pass (wire values preserved; the serialization change stays parked behind arcs).
> DEPENDS ON: nothing for docs/diagrams; the parked on-disk serialization change alone waits on STATBUS-071 arc coverage.

---

## Where this stands (2026-07-12)
Everything a reader or operator sees is DONE: the vocabulary registry is complete and ratified (doc/upgrade-vocabulary.md), the docs and all three diagrams speak it, the ~20 operator-facing log/error strings speak it (commit 6c90e2964), and the first identifier slice landed with wire values proven byte-identical (commit b2a54dc69).

Two residuals remain, BOTH deliberately parked behind STATBUS-071's arc campaign by architect ruling:
- (A) rename the post-swap FUNCTION family (resumePostSwap, applyPostSwap, postSwapFailure + ~250 coupled comments) — that family is exactly the code the arcs are proving right now; renaming mid-proof multiplies re-verification cost for a purely internal surface.
- (B) the on-disk Phase serialization values — changing what the flag file stores needs the arcs to prove cross-version recovery first.

When the 071 campaign settles, dispatch (A) to the engineer and rule (B) fresh. Nothing else is open here.

---

## Why
The upgrade + recovery vocabulary is obtuse — "pre-swap", "post-swap", "Resuming", "positively-behind", "at-target". The King's standard: plain language a reader gets without a glossary. "Booting the new binary" beats "the binary-swap commit boundary". The upgrade is the most safety-critical, most-reviewed code we have — its words must be the clearest.

## The plain forward-vs-rollback decision (the worked example + style anchor — DONE in the doc)
An upgrade has ONE point of no return: the moment the box BOOTS THE NEW BINARY. Before it = reversible prep (incl. the DB backup). After it = committed to new. On a crash-restart, recovery picks FORWARD (finish to new) or ROLL BACK (restore backup -> old). Rule: go forward whenever still possible; roll back only when CONFIRMED stuck behind.
- Crashed before booting the new binary -> roll back (trivial; no backup taken, restart on old).
- Crashed after booting the new binary -> is it already AT the new version?
  - Already at new -> finish forward; NEVER roll back (it may have served new + taken data the backup predates).
  - Confirmed behind -> roll back once to this upgrade's backup -> old.
  - Can't tell (DB unreachable) -> go forward (never destroy on a guess).
- Torn window (killed between a migration committing + being recorded) -> behind -> forward fails "relation already exists" -> roll back -> operator retries.
Landed as the "Forward vs rollback — in plain terms" subsection in doc/upgrade-timeline.md.

## Jargon -> plain map
- pre-swap / post-swap / "the binary-swap" -> before / after BOOTING THE NEW BINARY
- Resuming -> CONTINUING AFTER A CRASH-RESTART
- positively-behind / Behind -> CONFIRMED STUCK BEHIND THE NEW VERSION
- at-target / AtTarget -> ALREADY AT THE NEW VERSION
- ground truth -> WHAT'S ACTUALLY ON DISK (the binary + which migrations ran)
- rollback -> ROLL BACK TO THE OLD VERSION; forward / resume -> FINISH FORWARD TO THE NEW VERSION

## ONE BY ONE — and WHY (do NOT blind-sweep / ruplacer)
Classify EACH site: cosmetic vs load-bearing.
- SAFE (cosmetic): doc prose, code comments, operator-facing log/error strings, Go identifiers, ticket language. Rename freely.
- LOAD-BEARING (careful): the `Phase` enum WIRE values ("post_swap", "resuming") are serialized into the on-disk upgrade flag (UpgradeFlag JSON) by the OLD binary and read back by the NEW binary during recovery. Renaming the wire value BREAKS cross-version recovery (a box mid-upgrade carries the old-format flag). -> rename the Go IDENTIFIERS for clarity but KEEP the wire values (or read both old+new). Per-site judgment, never a sweep.
- The doc references the code's actual Phase values, so doc + code de-jargon are COUPLED: plain prose may name the wire value parenthetically until/unless the code rename lands.

## Targets (one by one)
1. doc/upgrade-timeline.md — the "five phases" + recovery-contract sections -> plain prose (the forward-vs-rollback subsection is the worked example).
2. doc/recovery/* — the recovery design docs -> plain.
3. STATBUS-046's escalation design -> plain language (when it is ratified / built).
4. Code: the `Phase` enum + recover/resume function names -> plain Go identifiers; KEEP the serialized wire values (load-bearing).
5. Operator-facing log + error strings on the upgrade/recovery path -> plain.
6. doc/diagrams/ — the THREE upgrade/recovery diagrams ONLY: upgrade-timeline.plantuml, upgrade-lifecycle.plantuml, install-recovery.plantuml. Plain prose in the labels/notes (de-jargon: pre-swap/post-swap, "ground truth decides direction", positively-behind, at-target, exit-42-handoff, QuiesceClients, flock, wedge -> the jargon->plain map above). COUPLED to target #4: the function-name + Phase references update WITH the code rename (don't half-rename). Regenerate each .svg from its .plantuml after editing. (The architecture / infra / git / domains diagrams are a DIFFERENT domain — NOT this jargon, OUT OF SCOPE.)

Each target = one commit; classify cosmetic-vs-load-bearing first; verify NO serialized/on-disk value changed (the flag must still round-trip old<->new).
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 doc/upgrade-timeline.md + doc/recovery/* + the 3 upgrade diagrams (upgrade-timeline / upgrade-lifecycle / install-recovery .plantuml, with .svg regenerated) read in plain language (no pre-swap/post-swap/Resuming/positively-behind/at-target jargon in prose); the forward-vs-rollback plain subsection is the style anchor
- [ ] #2 Code Go identifiers de-jargoned for clarity, but the serialized Phase WIRE values are PRESERVED (or both old+new read) — verified the on-disk upgrade flag still round-trips between an old and a new binary
- [ ] #3 Operator-facing log + error strings on the upgrade/recovery path are plain
- [ ] #4 Each site was classified cosmetic-vs-load-bearing and changed one-by-one (no blind sweep); STATBUS-046's escalation design de-jargoned when it lands
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
## Glossary walkthrough — LIVE STATE (architect; King-driven; updated 2026-06-26)

REGIME: "establish + apply a SLUG REGIME" (concept → kebab slug → plain message). Registry: doc/upgrade-vocabulary.md.

⚠️ PARKED (arc-gated): on-disk Phase serialization changes to match slugs (clean break, no read-both) + CLEAN RESTART on old/unrecognized sentinel. Safety hinges on restart-safety from a post-swap partial state — provable only by install-recovery arcs (STATBUS-071). Doc constraint section marked UNDER REVISION.

LOCKED (in the registry):
- PHASES: old-sb-upgrading ("") → old-sb-swap (exit 42) → new-sb-swapped (post_swap; arrived/self-heal) → new-sb-upgrading (resuming; running post-swap migrations). "Resuming" slug dissolved.
- UPGRADE STATES (9, snake_case): available → scheduled → in_progress → (completed|failed|rolled_back) → (skipped|dismissed|superseded). Full actor map (CLI/web/service) + 26 cols.
- SCHEDULING: claim-upgrade = sb claims + runs (executeUpgrade), runner = systemd service OR ./sb install (race-safe atomic claim).
- RECOVERY read pair: recorded-state (what was written down) vs observed-state (binary+migrations+flock, measured now).

RECOVERY DECISION TREE — fully mapped (11 paths), names HELD pending the model decision (STATBUS-110):
- acquire-retry: recovery-new-sb-retrying-db, recovery-new-sb-fetching-commit
- known recovery: recovery-old-sb-never-swapped, recovery-new-sb-completed-migrations, recovery-new-sb-pending-migrations
- human: recovery-stuck-needs-human, recovery-unexpected-state
- housekeeping: recovery-nothing-pending, recovery-discard-corrupt-flag, recovery-clear-install-flag
- edge: recovery-binary-mismatch

DESIGN SPIN-OUTS (discovered during the walkthrough — the conservative recovery model was a likely under-ratified agent assumption):
- STATBUS-109: in-process backoff for transient recovery errors (exit-restart creates noise).
- STATBUS-110: DB read-only window → rollback always data-safe → relaxes STATBUS-039 "never restore on a guess" → SIMPLIFIES the recovery tree. AUTHORITATIVE recovery-correctness plan; carries the King decision. THE recovery names depend on its outcome.

FINDINGS: liveness = flock not PID (install/state.go:5-8); the direct-PG path is ungated during the maintenance window (maintenance is HTTP-only) = the data-safety hole (STATBUS-110).

PRINCIPLES: name the subject (sb) · one emitter/slug · -ing=state, swap/swapped=event · where-we-are=Phase, where-we're-going=Action · invoker=audit field · name by STRATEGY (transient / known-recovery / human).

REMAINING vocabulary sections: Recovery ACTIONS (continue-upgrade / complete-upgrade / roll-back — gated on the STATBUS-110 model decision) → Mechanisms & artifacts (upgrade-sentinel, flock, db-snapshot/backup/restore, stop-clients, restart-loop, heartbeat).

DELIVERY: after each section locks, apply docs → diagrams → code → logs, one site at a time; foreman commits pathspec-scoped; code/wire rename LAST.

DIAGRAM CROSS-REF + 2 KING RATIFICATIONS (2026-06-26; mechanic-traced, foreman grep-verified; tmp/operator-recovery-cases-vs-diagrams.md).

Coverage of the 11 recovery cases vs the 3 upgrade/recovery diagrams: DRAWN as branches = cases 3,4,5,6,7,11; NOTE-ONLY (prose, not a drawn branch) = 8 (git-error→Unknown, upgrade-timeline:162-163) + 10 (FLAG_PHASE_UNKNOWN, :163-164/:204); TRUE GAPS (absent) = 2 (corrupt-flag), 1 (only the trivial clean-boot baseline; no-flag HANDLING is drawn at timeline:53/:202), 9 (stuck-needs-human ARRIVAL path; only the systemd reset-failed escape noted at install-recovery:174).

RATIFIED (King): (1) CORRUPT-FLAG (recovery-discard-corrupt-flag) = DISCARD-AND-LOG → boot normally (autonomous). Was undrawn AND unspecified — now SPECIFIED. (2) recovery-failed (the `failed` upgrade-state: a rollback was chosen but its RESTORE itself broke — rsync/disk) = NEEDS A HUMAN. DISTINCT from unexpected-state (can't-read-state) and from the dissolved stuck-needs-human; read-only does NOT help it (a broken restore is hands-on regardless).

FINAL simplified recovery model (post read-only window): autonomous in every case EXCEPT TWO human terminals — (a) unexpected-state (can't READ the phase; a decision), (b) recovery-failed (rollback RESTORE broke; an action-failure).

DIAGRAM DE-JARGON WORK (this task, target #6): draw the corrupt-flag case; promote git-Unknown + unrecognized-phase from prose footnotes to drawn branches; SPLIT the single failed/human blob into its two distinct reasons. + install-recovery:114 self-declares a test gap (pre-1.0 legacy-refuse path has no scenario).

GLOSSARY — RECOVERY SECTIONS CRYSTALLISED (King, 2026-06-27); doc/upgrade-vocabulary.md now carries, ratified:
• 'Recovery — when a step fails': `intermittent-error`/`persistent-error`/`unknown-error`; ONE `backoff-retry` strategy, two cases — `db-unreachable` (wall-clock-5s connect probe) + `commit-not-fetched` (STALL-not-deadline `git fetch`, ~60s no-progress, ~15min); container-not-ready EXCLUDED (own health loops); composition note (in front of systemd backstop; exhaust→roll-back; backstop=unknown only).
• 'Recovery — the two human stops': `unknown` (unrecognised error OR unreadable phase) + `restore-broke` (rollback's restore broke→hands-on; operator UX agreed in principle — print error + snapshot-path + re-run `./sb install`; impl grounding pending).
• Direction: the stale `state-unknown` ('continue forward, never destroy on a guess' — the OVERTURNED model) REPLACED by `position-unreadable` → routes to the error classifier.
Full crystallised model also in doc-019 §3-§4. Recovery slug names now UN-HELD (the 110 model is ratified). STILL OPEN in 107: the Mechanisms & artifacts names (entry 1 = the on-disk marker, in review; architect lean `upgrade-marker`) + the 3-diagram de-jargon (target #6).

MECHANIC PASS (2026-07-07): re-verified the two items the notes above flagged as "STILL OPEN" — both were stale.

1. Mechanisms & artifacts naming — doc/upgrade-vocabulary.md:179 already says "Mechanisms & artifacts are now locked too" (upgrade-in-progress, db-snapshot/-backup/-restore, db-dump, stop-app-services, restart-loop, heartbeat) and "The vocabulary is complete — only open item is the on-disk Phase serialization values (parked, arc-gated)". Nothing left to lock.

2. 3-diagram de-jargon (target #6) — the STRUCTURAL work (draw the corrupt-flag case, promote git-Unknown + unrecognized-phase from footnotes to drawn branches, split the failed/human blob into unknown vs restore-broke) was ALREADY DONE by an earlier pass not reflected in these notes: upgrade-timeline.plantuml:149-150 draws corrupt-flag (discard-and-log) and unrecognized-phase ([HUMAN: unknown]) as distinct alt-branches; upgrade-lifecycle.plantuml:36 (unknown self-loop) vs :51 (restore-broke → failed) are already two separate drawn transitions, not one blob. install-recovery.plantuml had zero remaining jargon.

What I actually found and fixed this pass — a REAL residual the notes missed entirely: target #5 (operator-facing log/error strings) had NOT been applied. cli/internal/upgrade/service.go and cli/cmd/root.go still spoke the pre-ratified vocabulary — "ground truth", "resuming-phase", "pre-swap"/"post-swap", "positively behind", "at-target" — in ~20 logRecover/progress.Write/fmt.Errorf strings actually shown to operators (upgrade log, DB error column, stderr), even though doc/upgrade-vocabulary.md had ratified observed-state/already-at-new/cannot-reach-new/continuing-after-crash-restart back on 2026-06-26/27. Rewrote all of them to the ratified vocabulary — text only, zero behavior change (Go identifiers GroundTruthAtTarget/Behind/Unknown, FlagPhasePreSwap/PostSwap/Resuming, and the serialized wire values all untouched). Also applied the final small lexical residue of stale jargon (at-target/positively-Behind/ground-truth/pre-swap/post-swap) in upgrade-timeline.plantuml and upgrade-lifecycle.plantuml and regenerated both .svg from source; install-recovery.plantuml needed no change.

STILL OPEN, intentionally not touched: (a) target #4, the Go identifier rename (GroundTruth/FlagPhase* etc.) — explicitly the engineer's job per this ticket's own STAGE line, and it's tightly coupled to ~100+ internal dev comments across service.go that use the same shorthand describing those identifiers; doing the string/diagram pass without renaming the identifiers first would make comments and identifiers disagree, so I left those comments as-is pending the identifier pass. (b) the parked on-disk Phase serialization change — explicitly arc-gated on STATBUS-071, not in scope for anyone yet.

Verified: go build ./..., go vet ./..., go test ./... all green in cli/ after every edit. No test pins the literal operator-facing strings I changed (checked via grep before editing).
<!-- SECTION:NOTES:END -->

## Comments

<!-- COMMENTS:BEGIN -->
author: foreman
created: 2026-07-06 23:39
---
OPERATOR-FACING STRING PASS SHIPPED: 6c90e2964 (2026-07-07). All ~20 operator-visible strings in service.go/root.go now use the ratified registry vocabulary (architect verified every slug against doc/upgrade-vocabulary.md; two corrections to exact registry terms applied at commit: the detail slug is new-sb-upgrading, the third verdict is position-unreadable). Diagrams' labels aligned + SVGs regenerated. The mechanic also corrected this ticket's stale 'STILL OPEN' notes (mechanisms-naming and diagram-structure work were already done). REMAINING — the ticket stays In Progress on exactly two named residuals: (1) the Go IDENTIFIER renames (GroundTruth* / FlagPhase* names; wire values untouched) — engineer slice; (2) the parked on-disk Phase serialization — arc-gated behind STATBUS-071.
---

author: foreman
created: 2026-07-07 00:00
---
IDENTIFIER SLICE SHIPPED: b2a54dc69 (2026-07-07). ObservedState family + Phase constant names now follow the registry slugs; wire values byte-identical (string-literal set-diff proof + flag round-trip tests); ~100 coupled comments de-jargoned with their identifiers; the one missed operator string fixed to the ratified wording; ground_truth_test.go → observed_state_test.go. THE TICKET'S PRECISE REMAINDER, both parked behind STATBUS-071 by architect ruling: (residual A) the post-swap FUNCTION-family rename — resumePostSwap, applyPostSwap, postSwapFailure, updateFlagPostSwap, writeFlagPhase, IsServiceForwardRecovery + ~250 coupled comment mentions, names to follow the registry slugs, lands AFTER the 071 arc campaign settles (that family is exactly the code the arcs exercise; renaming mid-proof multiplies re-verification cost for a purely internal surface); (residual B) the on-disk Phase serialization change — arc-gated, unchanged. Everything operator-visible and every wire value is done.
---
<!-- COMMENTS:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
CLOSED in the King's clean-ship pass (2026-07-12, architect-adjudicated). Everything a reader or operator ever sees speaks the ratified plain vocabulary: the registry (doc/upgrade-vocabulary.md) complete and King-crystallised; the docs and all three upgrade diagrams de-jargoned; the ~20 operator-facing log/error strings on the ratified slugs (6c90e2964); the first Go identifier slice landed with wire values proven byte-identical by round-trip tests (b2a54dc69); the forward-vs-rollback plain-language section standing as the style anchor. The two deliberately-parked residuals (the post-swap function-family rename and the on-disk Phase serialization — parked behind the arc campaign by architect ruling, since that family is exactly the code the arcs were proving) are re-homed as STATBUS-164, an honestly-To-Do completion sweep carrying the original parking rationale and the serialization half's re-ruling requirement — a parked In Progress becomes a truthful board state. The plain-language standard this ticket established (understood without a glossary; jargon-to-plain map; one-by-one cosmetic-vs-load-bearing classification) is now the house norm applied board-wide in the two clarity sweeps.
<!-- SECTION:FINAL_SUMMARY:END -->
