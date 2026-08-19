---
id: STATBUS-247
title: >-
  canary-topology: dev proves the candidate installs, Norway proves a person can
  install it
status: To Do
assignee: []
created_date: '2026-08-19 07:14'
updated_date: '2026-08-19 07:39'
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
A release candidate cannot currently be deployed as such, and nothing in our release ever rehearses what a customer actually does. The buttons that deploy to our boxes push whatever master's tip happens to be, so the box meant to prove the candidate proves something else; and every install we perform is a machine pushing a branch, which is not how any statistical office installs StatBus. This entry gives two boxes two different jobs, and the second one is new.

**dev — the automatic canary.** Every candidate installs itself, no human involved. It answers one question early and cheaply: can a real box, with real data, take this candidate at all? It gates the release chain — if dev cannot take the candidate, renting 31 machines to test fixtures is waste.

**Norway — the human canary.** The candidate is OFFERED and a PERSON installs it, following a written observation card. Not because automation is unavailable, but because the operator surface is the thing under test: the suggestion appearing, the decision prompt, the progress messages, where the operator lands afterwards. That is the entire experience a statistical office has of this software, and until now no release exercised it even once.

**Demo is not part of this.** It is an ordinary installation that follows releases on its own, like any other box — dev already answers the does-it-install question, and a second automatic slot would only repeat it. Demo is governed by STATBUS-248 along with the other channel-following installations.

WHAT ALREADY WORKS, and must not be rebuilt — the human role is reached by REMOVING machinery, not adding it:

- The deploy layer and the convergence oracle are sound. A push to a deploy branch pokes the box's upgrade service and polls until the box has converged, addressed by COMMIT. Neither needs changing.
- **"Offer without installing" already exists and is the default.** The upgrade service auto-discovers on its own poll and registers each newer release as a candidate in state 'available' — it does NOT schedule (cli/internal/upgrade/service.go:3965 `discover()` calls only `upsertCandidate`; both writes to state='scheduled' are explicit-target paths). A box nobody pushes at ALREADY sits waiting for a person.
- **The channel already means what we need.** `UPGRADE_CHANNEL=prerelease` selects release-candidate tags only (cli/internal/upgrade/github.go:295-297, 556-557), and standalone boxes are already authored that way (doc/CLOUD.md:769) — so Norway already sees candidates today. What changes is who acts on them.
- **`canarySlots` is already exactly right.** It lists dev and no (cli/cmd/release_canary.go:43-46). No slot is added or removed by this entry.

FIVE DECISIONS, ruled here so the builder does not have to guess:

**1. dev is driven by the chain, not by the channel.** "Auto-install the latest candidate" sounds channel-shaped, and the channel mechanism genuinely exists — so this was re-argued with it in hand. It still loses, for one reason: the chain needs a SYNCHRONOUS verdict. Discovery ticks on a long interval and only offers; the chain would have nothing to wait on. Pointing dev's deploy branch at the tag's commit gives an immediate, deterministic install and a verdict the chain can gate on. Setting `UPGRADE_CHANNEL=prerelease` on dev as well is a harmless backstop — discovery can only offer, so it cannot become a second installing path.

**2. Norway needs no new mechanism — only the removal of the push.** It is already on the prerelease channel, so the existing discovery already offers it every candidate. Stop writing its deploy branch (STATBUS-244) and the offer simply sits there until a person acts. The operator's action is the real one: `./sb upgrade schedule <tag>`, or `./sb install`. **Nothing automated may call schedule, apply-latest, or install on Norway.** That is the whole boundary, and it is the one thing an implementer could plausibly get wrong.

**3. Cadence: promotion-bound candidates only, not every cut.** A person is not asked to install every RC. The gate enforces this naturally and needs no extra rule — only a promotion requires a completed row on Norway, so candidates nobody intends to promote are simply never acted on. Their offers sit unclaimed, which is the correct resting state and not a fault. The chain therefore does nothing at all to Norway; if an operator wants the offer sooner than the next poll, `./sb upgrade check` is theirs to run.

**4. The observation card is the deliverable that makes this more than a manual deploy.** A written card the operator follows, naming what they SHOULD see at each step: the suggestion text, the decision prompt, the progress messages, and where they land after the upgrade. The operator records what they actually saw. **Any deviation files a ticket before promotion** — that is what converts a person clicking through into an observation with a verdict. The card's CONTENT is operator-surface work and goes to the King for approval at build time, in the same lane as the error-wording work; this entry fixes only that the card exists, is followed, and gates.

**5. The gate's per-slot advice must match each box's role.** `checkOneCanary`'s failure hints print `git push -f origin master:ops/...` per slot (cli/cmd/release_canary.go:136-143). Those commands stop existing under STATBUS-244, and on Norway the hint would be actively harmful — an operator following it would bypass the operator surface the slot exists to prove. dev's hint points at the chain; Norway's prints the operator command to run on that box. Waiting on a person is an expected, open-ended, named state, never an unexplained silence — STATBUS-245 specifies it.

WHY THAT HELPS: promotion stops being a check we run on the software and becomes a rehearsal of the customer's experience. If the offer never appears, or the message is confusing, or the documented command fails, a ticket is filed and the release stops — which is exactly the surface our operator-facing error work and the deployments in African statistical offices exist for. Every promoted release now proves a person can install it, because a person just did, and wrote down what they saw.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Tagging a candidate installs it on dev with no human action, through the existing deploy and convergence layers unchanged
- [ ] #2 dev's convergence runs first in the chain and its failure stops the chain before any VM fleet is dispatched
- [ ] #3 Norway is OFFERED each candidate — a candidate row in state 'available' appears — and is installed by no automated path whatsoever
- [ ] #4 Nothing automated calls schedule, apply-latest, or install on Norway; a test pins this boundary so a future change cannot quietly automate the human canary
- [ ] #5 A person installs the promotion-bound candidate on Norway following the observation card, and that act is what satisfies the promotion gate
- [ ] #6 The observation card exists as a written artifact naming what the operator should see at each step — suggestion, decision prompt, progress messages, post-upgrade landing — and its content is approved by the King before first use
- [ ] #7 Any deviation between the card and what the operator actually saw files a ticket, and promotion does not proceed until those tickets are triaged
- [ ] #8 Candidates nobody intends to promote leave an unclaimed offer on Norway, and that is treated as the correct resting state rather than a failure
- [ ] #9 Demo is not in the promotion gate and is not pushed to by anything — it follows releases on its own under STATBUS-248
- [ ] #10 canarySlots still lists exactly dev and no, and each slot's failure hint names the action appropriate to its role — no hint tells an operator to push a deploy branch
- [ ] #11 The stable promotion gate refuses until Norway carries a completed upgrade at the candidate's exact commit, with the wait explained per STATBUS-245
- [ ] #12 Proven end to end on a real cut: tag → dev converges → fleet → offer sits on Norway → a person installs it against the card → gate clears
<!-- AC:END -->

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
<!-- COMMENTS:END -->
