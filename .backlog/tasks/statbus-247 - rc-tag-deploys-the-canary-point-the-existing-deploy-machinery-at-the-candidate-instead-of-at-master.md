---
id: STATBUS-247
title: >-
  canary-topology: one box proves the candidate installs, two boxes prove a
  person can install it
status: To Do
assignee: []
created_date: '2026-08-19 07:14'
updated_date: '2026-08-19 07:36'
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
A release candidate cannot currently be deployed as such, and nothing in our release ever rehearses what a customer actually does. The buttons that deploy to our boxes push whatever master's tip happens to be, so the box meant to prove the candidate proves something else; and every install we perform is a machine pushing a branch, which is not how any statistical office installs StatBus. This entry fixes both by giving the three boxes three different jobs.

THE TOPOLOGY:

**dev — the automatic canary.** Every candidate installs itself, no human involved. It answers one question early and cheaply: can a real box, with real data, take this candidate at all? It gates the release chain — if dev cannot take the candidate, renting 31 machines to test fixtures is waste.

**demo and no — the human-fidelity canaries.** The candidate is OFFERED to these boxes and a PERSON installs it. Not because automation is unavailable, but because the operator surface is the thing under test: the suggestion appearing, a human deciding, the command running, the messages it prints. That is the entire experience a statistical office has of this software, and until now no release exercised it even once.

**Promotion gates on the human-performed installs.** dev's automatic completion gates the chain; demo's and no's human-performed completions gate the stable promotion.

WHAT ALREADY WORKS, and must not be rebuilt — this topology is mostly achieved by REMOVING machinery, not adding it:

- The deploy layer and the convergence oracle are sound. A push to a deploy branch pokes the box's upgrade service and polls until the box has converged, addressed by COMMIT. Neither needs changing.
- **The "offer without installing" behaviour already exists and is the default.** The upgrade service auto-discovers on its own poll and registers each newer release as a candidate in state 'available' — it does NOT schedule (cli/internal/upgrade/service.go:3965 `discover()` calls only `upsertCandidate`; both writes to state='scheduled' are explicit-target paths). So a box nobody pushes at ALREADY sits waiting for a person. Demo and no become human-fidelity the moment we stop pushing at them.
- **The channel already means what we need.** `UPGRADE_CHANNEL=prerelease` selects release-candidate tags only (cli/internal/upgrade/github.go:295-297, 556-557). Standalone boxes are already authored this way (doc/CLOUD.md:769) — so putting our canaries on candidates is existing practice, not a new exposure.

FOUR DECISIONS, ruled here so the builder does not have to guess:

**1. dev is driven by the chain, not by the channel.** The phrasing "auto-install the latest candidate" sounds channel-shaped, and the channel mechanism genuinely exists — so this was re-argued with it in hand rather than inherited. It still loses, for one reason: the chain needs a SYNCHRONOUS verdict. Discovery ticks on a long interval and only offers; it would never schedule, and the chain would have nothing to wait on. Pointing dev's deploy branch at the tag's commit gives an immediate, deterministic install and a verdict the chain can gate on. Setting `UPGRADE_CHANNEL=prerelease` on dev as well is harmless and worth doing as a backstop — because discovery only ever offers, it cannot become a second installing path, so the box still has exactly one.

**2. demo and no need no new mechanism at all — only the removal of the push.** Set `UPGRADE_CHANNEL=prerelease`, stop writing their deploy branches (STATBUS-244 removes the buttons that did), and the existing discovery offers each candidate. The operator's action is the real one: `./sb upgrade schedule <tag>`, or `./sb install`. The chain MAY poke `./sb upgrade check` on these boxes so the offer appears promptly instead of on the next poll — that is an offer, not an install. **The chain must never call `schedule`, `apply-latest`, or `install` on a human-fidelity slot.** That is the whole boundary, and it is the one thing an implementer could plausibly get wrong.

**3. Ordering: dev gates the chain, the fleet runs, then the humans.** dev first and stop-on-failure, matching the cheapest-first logic the chain already uses. Demo and no are offered once the fleet is green — they are the last gate before promotion, and a person should not be asked to install a candidate the fleet has not cleared.

**4. The gate covers three slots, and its advice must be per-role.** `canarySlots` (cli/cmd/release_canary.go:43-46) grows demo. Its failure hints currently print `git push -f origin master:ops/...` per slot (lines 136-143). Those commands stop existing under STATBUS-244, and on a human-fidelity slot they would be actively harmful — an operator following the hint would bypass the operator surface the slot exists to prove. dev's hint points at the chain; demo's and no's print the operator command to run on that box. Waiting on a person is an expected, open-ended, named state, never an unexplained silence — STATBUS-245 specifies it.

Note the deliberate asymmetry with production: canaries are candidate-driven because the release chain needs a verdict about a specific candidate. Production is recommended to follow the stable channel (STATBUS-248) because nobody gates on it. Different mechanisms across the fleet, exactly one per box.

WHY THAT HELPS: promotion stops being a check we run on the software and becomes a rehearsal of the customer's experience. If the offer never appears, or the message is confusing, or the documented command fails, the release stops — which is exactly the surface our operator-facing error work and the deployments in African statistical offices exist for. Every release now proves a person can install it, because a person just did.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Tagging a candidate installs it on dev with no human action, through the existing deploy and convergence layers unchanged
- [ ] #2 dev's convergence runs first in the chain and its failure stops the chain before any VM fleet is dispatched
- [ ] #3 demo and no are OFFERED the candidate — a candidate row in state 'available' appears on both — and neither is installed by any automated path
- [ ] #4 The chain never calls schedule, apply-latest, or install on demo or no; a test pins this boundary so a future change cannot quietly automate a human-fidelity slot
- [ ] #5 A person installs the candidate on demo and no using the documented operator command, and that act is what satisfies the promotion gate
- [ ] #6 canarySlots covers dev, demo and no, and each slot's failure hint names the action appropriate to its role — no hint tells an operator to push a deploy branch
- [ ] #7 The stable promotion gate refuses until demo and no both carry a completed upgrade at the candidate's exact commit, with the wait explained per STATBUS-245
- [ ] #8 Proven end to end on a real cut: tag → dev converges → fleet → offer appears on demo and no → a person installs both → gate clears
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
<!-- COMMENTS:END -->
