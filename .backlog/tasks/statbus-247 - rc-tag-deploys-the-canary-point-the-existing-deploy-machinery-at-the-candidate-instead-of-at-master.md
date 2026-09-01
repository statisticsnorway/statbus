---
id: STATBUS-247
title: >-
  canary-topology: dev proves the candidate installs, Norway proves a person can
  install it
status: In Progress
assignee:
  - '@tester'
created_date: '2026-08-19 07:14'
updated_date: '2026-09-01 07:27'
labels:
  - release
  - ops
  - upgrade
dependencies: []
references:
  - .github/workflows/master-to-dev.yaml
  - .github/workflows/deploy-to-dev.yaml
  - ops/ci-deploy-status.sh
  - .github/workflows/release-fleet-orchestrator.yaml
priority: high
type: enhancement
ordinal: 240000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
PURPOSE: give the release chain its running order, and give the two staffed boxes their distinct jobs — dev proves a candidate installs, automatically; Norway proves a person can install it through the operator surface.

WHAT THE SYSTEM ALREADY DID WELL, unchanged by this ticket: one code path from the UI's install button through the CLI to the box — clicking in the admin UI and running `./sb upgrade schedule` are the same mechanism the entire way. Deployments triggered by writing a branch are part of that same composable design: a branch write is an event, the event runs the same code any operator runs. That design is deliberate and stays.

THE TWO GAPS THIS TICKET CLOSED, at their actual scope:

1. TARGET SELECTION. The manual master-to-X dispatch workflows chose master's tip as the deploy target — an untagged, ungated commit — instead of a named release candidate. The transport was sound; the target choice was the gap. Fixed: the release chain dispatches deploy-to-dev naming the candidate's exact commit, and the master-addressed dispatch workflows are removed (STATBUS-244, completed by 244b).

2. REHEARSAL. The release process had no stage in which a person performed an install through the operator surface — the offer appearing, the prompt, the landing afterwards. Added: Norway as the human canary. The offer sits until a person acts, using the same UI/CLI path as any operator anywhere; the completed install satisfies the promotion gate.

THE CHAIN, cheapest and most disposable first, each stage gating the next:
  1. SMOKE — fresh install, and install-then-upgrade, on ephemeral VMs (both paths: dev is upgraded rather than installed, so install-only smoke would miss what dev needs).
  2. DEV — the chain installs the candidate on a real box with real data.
  3. THE FULL SUITES — run only for a candidate that survived smoke and dev.
  4. NORWAY — a person installs the promotion-bound candidate. The wait is open-ended by design: Norway's scale surfaces what fixtures cannot.
  5. PROMOTION — requirements unchanged.

DECISIONS ON RECORD, kept so they are not re-litigated:
- Dev is chain-driven, not channel-driven: the chain needs a synchronous verdict; discovery only offers.
- Norway needed no new mechanism — discovery already registers offers without scheduling; the change was removing the push, so the person's act is the only install path there.
- A separate QA instance was considered and rejected: dev IS the QA instance; a hurt dev exercising the recovery machinery is a benefit, and a scripted reinstall is the bounded worst case.
- Cadence: promotion-bound candidates only. Unclaimed offers on Norway are the correct resting state, not neglect.
- Demo is not part of the gate; STATBUS-248 governs it.
- The observation card is voluntary practice, not a gate — the King's ruling at 8b5487372: the completed install is what the gate checks.

STATE: built and in use across real cuts. Remaining: the end-to-end observation on one candidate (final acceptance criterion).
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 The chain runs in order: smoke → dev → suites → Norway → promotion, each stage gating the next
- [x] #2 Smoke covers both happy paths on ephemeral machines; a failure stops the chain before dev is touched
- [x] #3 Tagging a candidate installs it on dev with no human action, through the existing deploy layer unchanged
- [x] #4 dev's failure stops the chain before the expensive suites are dispatched
- [x] #5 Norway is offered each candidate and installed only by a person, through the same UI/CLI path as any operator
- [x] #6 Norway's target is a release candidate, never an arbitrary commit
- [ ] #7 The operator can see the smoke and suite results before deciding; waiting is the default
- [x] #8 A person's completed install on Norway is what satisfies the promotion gate
- [x] #9 Candidates nobody promotes leave an unclaimed offer on Norway — the correct resting state
- [x] #10 Demo is not in the promotion gate; STATBUS-248 governs it
- [x] #11 canarySlots lists exactly dev and no; each slot's failure hint names the action fitting its role
- [ ] #12 Observed end to end on one candidate: smoke → dev converges → suites → offer sits on Norway → a person installs → gate clears
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
**Observation-card gate LANDED at 9b823cc82** (mechanic's close-out unit, foreman-reviewed diff + independently re-ran the 245/247/card tests green): doc/observations/TEMPLATE.md promotes the King-approved doc-035 draft with <CANDIDATE_TAG> placeholders; checkOneCanary refuses a 'completed' operator-slot canary without a card at doc/observations/<tag>.md that NAMES the tag in its body (stale-copy guard); missingObservationCardReason is a pure unit-tested function; awaiting-operator resting state untouched and now prints the card path at offer time; red-verified structurally. REMAINING on this ticket: the live proof — Norway installs a candidate (rc.17, overnight-approved), the King records the first real card in the morning, and the gate is observed refusing-then-passing on real state. STATBUS-273 unblocks on that proof.

**GATE AMENDED BY THE KING (2026-08-31, 8b5487372):** the observation-card REQUIREMENT is retired from the promotion gate — ruled at a live blocked promotion of v2026.08.1: 'It should be enough that the Norwegian installation has been done and was a success, and that is it. And then there is a matter of discipline to actually report.' The completed-install check on the human-canary slot STAYS (AC#9's install act still satisfies the gate); the card remains as practice — the template survives (reworded: the gate only checks that the install completed, it does not read this file), the offer print still names the card path as discipline. The retirement is test-pinned (completed branch returns true unconditionally; the deleted card-check function may not exist in source), so the gate cannot quietly return. AC#10/#11's card-gating language is superseded by this ruling; the rc.17 card (doc/observations/v2026.08.0-rc.17.md) stands as the first and now-voluntary exemplar.
<!-- SECTION:NOTES:END -->

## Comments

<!-- COMMENTS:BEGIN -->
author: architect
created: 2026-08-19 07:28
---
AMENDED for the King's retire-the-buttons ruling. Two lines in this entry said the manual master-to-X buttons "stay for deliberate ad-hoc operations and leave the release path", and AC#5 asserted the same. That is now WRONG: under his ruling no master-addressed path survives anywhere, for any slot — see the amended STATBUS-244. Read this entry with that correction; the builder should treat AC#5 as struck and 244 as the authority on what happens to the buttons.

WHAT DOES NOT CHANGE, and is the reason the two entries compose rather than collide: the deploy BRANCHES stay, as this design's transport. 247 writes them automatically, addressed at a tagged commit; 244 removes only the human-facing buttons that used to write them with master's tip. Retiring the branches as well would delete the transport this entry depends on — the distinction between the button and the branch is what makes both rulings implementable at once.

Also note the asymmetry now visible across the packet, and that it is deliberate: the CANARIES are tag-driven (this entry) because the release chain needs a synchronous verdict — it must know NOW whether a real box took the candidate. PRODUCTION is recommended to be channel-driven (STATBUS-248) because nobody gates on it, so an autonomous tick is not a delay. Different mechanisms across the fleet, exactly one per box — which is what STATBUS-244 requires, and not a contradiction of it.
---

author: architect
created: 2026-08-19 07:36
---
TOPOLOGY REVISED (King's ruling 4). This entry previously specified two canaries, both automatic: dev gating the chain, Norway auto-deploying once the fleet went green. It now specifies three boxes in two roles, and the second role is the whole point of the change — demo and no are installed BY A PERSON, so that every promotion rehearses the operator surface rather than only the software.

CORRECTING MY OWN COMMENT #1 ABOVE, which is now stale in two ways. First, it tells the builder to treat AC#5 as struck; the acceptance criteria have since been rewritten wholesale and no such criterion exists. Read the current list, not that instruction. Second, it says the CANARIES are tag-driven because the release chain needs a synchronous verdict. That is now true of DEV ONLY. Demo and no are candidate-OFFERED and human-installed, and their wait is deliberately open-ended — the opposite of synchronous. The asymmetry it draws against production still holds, but the line is no longer canary-versus-production; it is chain-gating, human-gating, and channel-following: three roles across four boxes.

WHAT THE MECHANISM CHECK CHANGED, recorded because it moved a decision rather than confirming one. I expected offer-without-installing to need building, and it does not. The upgrade service already discovers and registers candidates as 'available' without ever scheduling — cli/internal/upgrade/service.go:3965, where discover() calls only upsertCandidate; both writes to state='scheduled' are explicit-target paths. UPGRADE_CHANNEL=prerelease already means candidates-only (cli/internal/upgrade/github.go:295-297), and standalone boxes are already authored that way (doc/CLOUD.md:769) — so running our canaries on candidates is existing practice, not a new exposure this ruling introduces. The human-fidelity role is therefore reached by REMOVING the push, not by adding a gate, which is why it costs almost no new machinery. The same check cut the other way on dev: the channel mechanism genuinely exists and still loses there, because discovery only ever offers and the chain needs something to wait on.

ONE CONSEQUENCE I DERIVED RATHER THAN INHERITED, flagged so it can be rejected in a line. If nothing legitimately writes demo's and no's deploy branches any more, leaving those branches and their deploy-to-X workflows live keeps a working push-to-install path aimed at exactly the two boxes whose value depends on a human performing the install. I folded that into STATBUS-244 as AC#4 rather than leaving it implicit. It follows from the King's own rule plus this topology, but he did not say it, so it is marked as mine.

A STALE COMMENT FOUND WHILE VERIFYING, worth fixing in passing because it would mislead whoever implements this: cli/internal/upgrade/service.go:5305 refers to "the discovery loop's auto-schedule". There is no such thing — discovery only registers. The prose is left over from an earlier design and is exactly the kind of load-bearing-sounding sentence this packet keeps tripping over.
---

author: architect
created: 2026-08-19 07:39
---
FINAL TOPOLOGY (King, in discussion with the foreman). Read this comment and the current description; comments #1 and #2 above are superseded on the points below and are kept only as the record of how the design moved.

WHAT CHANGED FROM COMMENT #2: it says demo and no are BOTH human-fidelity canaries. That is now wrong. **Demo is out of the gate entirely** — the King's reasoning is that demo would have been answering the does-it-install question, and dev already answers it. Demo becomes an ordinary installation following releases on its own, governed by STATBUS-248. **Norway is THE human canary**, singular.

WHAT THIS COSTS IN CODE: nothing. I had written that canarySlots must GROW to include demo. It must not — and it never needed to. The list is already exactly dev and no (cli/cmd/release_canary.go:43-46), which is what the King meant by demo costing the gate nothing it needed. My earlier instruction to add a slot was the error; verified before writing it down this time.

THE OBSERVATION CARD is what makes this more than a manual deploy, and it is the part with no existing mechanism behind it. A written card naming what the operator SHOULD see — suggestion text, decision prompt, progress messages, post-upgrade landing — against which they record what they actually saw, with any deviation filing a ticket before promotion. Without the card this is just a person doing by hand what a machine did before, which would be strictly worse than automation. With it, the release acquires a verdict about the operator surface that no automated check can produce. The card's CONTENT is operator-surface work and goes to the King at build time, same lane as the error-wording work; this entry fixes only that it exists, is followed, and gates.

CADENCE, per the foreman's sharpening and ratified in the King's read-back: promotion-bound candidates only, not every cut. Worth stating why this needs no enforcement mechanism — only a promotion requires a completed row on Norway, so a candidate nobody promotes is simply never acted on. I made the resting state explicit in AC#8 because an unclaimed offer sitting on a production box for weeks looks like neglect to anyone who has not read this entry, and someone will eventually try to tidy it away.
---

author: architect
created: 2026-08-19 09:07
---
CHAIN ORDER FINALIZED by the King. Comments #1 and #2 above are superseded on the topology; read the current description. What this comment adds is the reasoning behind the two new parts, so neither gets optimized away later.

SMOKE IS TWO PATHS, NOT ONE, and the second is the one that would have been dropped. A fresh install passing does not mean an install-then-upgrade passes, and dev is UPGRADED rather than installed — so a candidate that installs cleanly but cannot be upgraded onto would sail through a single-path smoke and fail at the first stage that costs us something we care about. Anyone trimming the chain for time will see two happy paths and assume one covers the other. It does not, and the one they would cut is the one that matches what dev actually does.

THE QA INSTANCE IS RECORDED AS REJECTED, WITH ITS REASONING, ON PURPOSE. It is an attractive idea — put something sacrificial in front of the canary — and it will be proposed again by anyone who watches a bad candidate hurt dev. The King's own conclusion dissolves it: dev IS the QA instance, so a second one answers the same question twice. I wrote the three mitigations into the entry rather than just the verdict, because a bare 'rejected' invites re-litigation while the reasoning ends it. The middle mitigation is the one worth internalizing: exercising the recovery machinery on a hurt dev is a BENEFIT. Recovery machinery that never runs is the actual risk, and this arrangement runs it on the box where running it is cheapest.

ORDERING RATIONALE, stated once: everything at smoke and everything in the fleets is disposable; dev is not. That single asymmetry determines the whole order — disposable things go first and filter for the irreplaceable one, and the irreplaceable one filters for the expensive ones. It is the same cheapest-first logic the chain already used, with 'cheapest' correctly understood as including what a failure costs to clean up rather than only what a run costs to rent.

NORWAY'S DEFAULT IS TO WAIT, and I made proceeding-early deliberate rather than merely allowed. If proceeding early is as easy as waiting, it becomes the norm under time pressure and the fleet stops gating anything in practice — the gate would still exist and would still be satisfied, just always after the fact.
---

author: foreman
created: 2026-08-19 09:30
---
KING APPROVED 2026-08-19 (dialogue presentation, fifth of the sitting), with his reason for Norway's open-ended wait recorded as design intent, near verbatim: "Norway's wait is open-ended by design because it's a HUGE installation — so we can catch those exact crazy things that take too long, or some migration logical error. That's the only way." The human canary's value is SCALE: real production-sized data surfaces what fixtures and small boxes structurally cannot — fold that sentence into the observation card's purpose statement at build time.
---

author: foreman
created: 2026-08-31 19:44
---
Foreman (2026-08-31 evening, under the King's drain-the-backlog directive): smoke stage (stage 1) dispatched to the tester NOW — reuse the install-recovery harness's VM provisioning; check whether existing scenarios already ARE the two happy paths before writing new ones; no paid runs without foreman gate. The tag-driven dev deploy (stage 2's trigger, retiring the transitional master-to-dev button per 244b) queues to the engineer behind 330. The 12-day gap between the King's approval and this dispatch is the deferral pattern he called out tonight; it ends here.
---

author: foreman
created: 2026-08-31 19:50
---
CORRECTION + SCOPE PIVOT (foreman, 2026-08-31 evening): my dispatch comment above was WRONG — the smoke stage is NOT unbuilt. Tester's assessment, foreman-verified: test-install.yaml + test-upgrade.yaml run 0-happy-install / 0-happy-upgrade on ephemeral VMs and the orchestrator gates the chain on both (release-fleet-orchestrator.yaml:376-391, needs + success conditions) — built during the release campaign, proven green on real rc tags (incl. the v2026.08.1 preflight). AC#1–#4 are satisfied. TRUE RESIDUE, tester re-dispatched: (a) delete master-to-dev.yaml — STATBUS-244b, unblocked since the tag-driven deploy is landed and proven (deploy-to-dev.yaml STAYS: button vs branch); (b) verify AC#5–#15 one by one with file:line evidence, building any missing pin (AC#6's nothing-automated-touches-Norway test, AC#14's per-role failure hints); (c) AC#16's end-to-end proof rides the King's next real cut.
---

author: foreman
created: 2026-08-31 19:55
---
Foreman (2026-08-31 night): residue LANDED at 3be54e416 — master-to-dev.yaml DELETED (244b complete; the orchestrator's candidate-addressed dispatch proven as the transport across 10+ rc cuts), deploy-to-dev.yaml + doc/CLOUD.md transitional notes now record the deletion, and AC#6's structural pin built: no workflow may combine a Norway target with schedule/apply-latest/install (TestNothingAutomatedSchedulesOnNorway_STATBUS247_AC6; foreman review closed a single-line-run: escape in the first draft, red-verified both directions). ACs #1-#7 and #12-#15 checked with evidence (tester's table in tmp/statbus-247-ac-verification.md); #8-#11 stand as landed/amended per the implementation notes (card retired by the King, completed-install check stays). REMAINING: AC#16 alone — the end-to-end proof on a real cut, which is the King's morning candidate: smoke → dev converges → fleets → offer sits on Norway → a person installs. The ticket closes on that observation.
---

author: foreman
created: 2026-09-01 06:30
---
KING'S RULING (2026-09-01 morning) — AC#6's PIN REMOVED at 082591313, and the criterion's test-pin clause is SUPERSEDED: 'That pin is what I call over-engineering. Some AI imagines it has to prevent future AI from doing something and writes code to prevent the future from going bad. We cannot anticipate the future, we can only answer for the current. Paranoia should not drive our coding.' The BOUNDARY stands (a person installs on Norway; nothing automated does — true by the design that made it true); the TEST enforcing it against hypothetical future edits is gone. Distinction on record for future test-writing: pins on PROPERTIES the current code depends on (memo keys, last-writer, completeness) remain legitimate regression tests; pins on POLICY against imagined future actors are the over-engineering this ruling forbids. Same-morning sibling ruling on STATBUS-329: the released-migration down guard judged 'too much but not harmful since there is an escape hatch' — accepted over-caution, softened on his word if it ever obstructs the legitimate down-fix-up loop.
---

author: foreman
created: 2026-09-01 07:27
---
KING'S LANGUAGE RULING + DESCRIPTION REWRITE (2026-09-01): the original description is replaced. His critique, on the record: the old opening ('a release candidate cannot currently be deployed as such', 'nothing in our release ever rehearses what a customer actually does', 'the buttons push whatever master's tip happens to be') was CLICKBAIT — alarm-shaped language suggesting a big mistake or omission in the whole system, when the system was deliberately designed with ONE code path from the UI button through the CLI to the box, and branch-triggered deployment is part of that same composable, principled design. The actual gaps were narrow — the master-to-X workflows' TARGET CHOICE (master's tip instead of a named candidate) and the absence of a human-rehearsal stage — and the rewrite states them at that scope. Standing rule from this ruling, applied to all future tickets and reports: describe a gap at its actual scope in plain calm language; never let a narrow defect's framing indict the sound design around it. The acceptance criteria are also cleaned: the removed AC#6 pin clause (superseded same morning, 082591313) and the retired card-gating clauses are gone; the person-install-satisfies-gate criterion is checked on the evidence of both real promotions (v2026.08.0 and v2026.08.1 each passed on Norway's completed row).
---
<!-- COMMENTS:END -->
