---
id: STATBUS-244
title: >-
  retire-master-to-x: no path should be able to deploy an untagged commit to a
  real installation
status: Done
assignee: []
created_date: '2026-08-19 07:10'
updated_date: '2026-08-27 13:50'
labels:
  - release
  - ops
dependencies: []
references:
  - .github/workflows/deploy-to-dev.yaml
  - .github/workflows/deploy-to-rune-no.yaml
  - doc/CLOUD.md
priority: high
type: chore
ordinal: 237000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Every button we have for deploying to a real installation deploys whatever master's tip happens to be. That is the opposite of the rule the release process now follows — only a named release candidate should ever reach an installation — and it is not a canary problem, it is true of every slot those buttons point at.

WHAT GOES WRONG: master's tip is not a release. It has no tag, no candidate row, no artifacts anyone gated on, and it changes every time someone commits. A button that deploys it to a live installation can put a version on a box that no gate ever examined, and nothing about the resulting box can be described except by naming a commit that was never blessed. This is not hypothetical: it is how the canary came to be running the wrong thing, and the canaries are only the slots where we happened to notice.

THE DETAIL: the nine master-to-X workflows predate both the cloud tooling and the ability to address a specific release candidate. They exist because, at the time, a branch tip was the only thing that could be pointed at a box. That is no longer true — a candidate can be addressed directly, and STATBUS-247 makes a tag deploy itself.

THE FIX: remove the nine master-to-X workflows and the documented procedure that tells people to use them. Afterwards no master-addressed path to an installation exists anywhere — and if a deliberate ad-hoc deployment is ever needed, it must be candidate-addressed, either by scheduling a specific version on the box or by cutting one.

WHAT HAPPENS TO EACH DEPLOY BRANCH DEPENDS ON THE BOX'S ROLE, and this is the one part not to get wrong:

- **dev keeps its branch.** It is the automatic canary, and the branch is the transport STATBUS-247's tag-driven deployment rides on — written by automation, addressed at a tagged commit, never touched by a person. Removing it would delete the mechanism that replaces the button.
- **Norway does not.** It is the human canary: the candidate is offered and a PERSON installs it against an observation card, because the operator surface is the thing under test. A live deploy branch there is a standing bypass of exactly that gate, and the first time someone is in a hurry it will be used.
- **Demo does not either, for a different reason.** It is an ordinary installation that follows releases on its own (STATBUS-248). A push would override the box's own source of truth about what it should be running.

So the rule is not "buttons go, branches stay". It is: **a push-to-install path survives only where an automated push is the intended way that box gets its software.** That is dev, and only dev.

TWO THINGS IN THE SWEEP THAT ARE NOT LIKE THE OTHERS: master-to-production and production-to-all. Retiring them is correct for the same reason, but it leaves an open question this entry deliberately does not answer — **how a promoted stable release reaches the production slots at all**. That is a policy decision, not a mechanism gap, and it is filed separately as STATBUS-248 rather than folded in here, because the answer changes what an operator experiences on promotion day and is the King's to make.

WHY THAT HELPS: after this, the only way a version reaches an installation is by being a release someone named — so "what is running on that box, and who decided?" always has an answer, and the answer is always a tag.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 All nine master-to-X workflows are removed, and no remaining path can deploy an untagged commit to any installation
- [x] #2 The documented deployment procedure (AGENTS.md and doc/) no longer instructs anyone to push master to a deploy branch
- [ ] #3 dev's deploy branch and deploy-to-dev workflow are UNCHANGED and keep working as STATBUS-247's transport — written by automation, addressed at a tagged commit, never touched by a person
- [ ] #4 No automated push-to-install path survives for demo or no. Norway is the human canary (STATBUS-247) and demo follows releases on its own (STATBUS-248); in both cases a push would override the box's own source of truth, and on Norway it would bypass the human gate outright
- [ ] #5 Any remaining deliberate version-to-box action is candidate-addressed: scheduling a named version on the box, or cutting one
- [ ] #6 master-to-production and production-to-all are removed as part of the sweep, with STATBUS-248 answering how stable reaches production before or alongside their removal
<!-- AC:END -->

## Comments

<!-- COMMENTS:BEGIN -->
author: architect
created: 2026-08-19 07:27
---
AMENDED to the King's ruling: the master-to-X buttons RETIRE ENTIRELY. My original text kept them "for deliberate ad-hoc operations", and that was wrong — his rule is that only a named candidate reaches an installation, and a master-addressed button contradicts it for EVERY slot, not only the canaries. The foreman's judgement that no use case survives is correct and I agree with each leg: an emergency ships via a cut, which is cheap now; and any deliberate version-to-box action already has a candidate-addressed form.

THE DISTINCTION PRESERVED, because losing it would break STATBUS-247: the BUTTONS retire, the deploy BRANCHES stay. Those branches are the transport 247's tag-driven deployment rides on — deploy-to-X listens on them. After this they are mechanism only: written by automation, addressed at a tagged commit, never touched by a person. Retiring the branches too would delete the transport of the very design that replaces the buttons.

PRODUCTION SPLIT OUT RATHER THAN FOLDED, per the foreman's instruction: master-to-production and production-to-all belong in the sweep, but removing them leaves a real question — how a promoted stable release reaches the production slots. That is a policy decision about promotion day, not a mechanism gap, so it is STATBUS-248 with my recommendation, for the King to approve or redirect on its own terms.
---

author: architect
created: 2026-08-19 07:36
---
NARROWED by the King's ruling 4 (the three-role canary topology, STATBUS-247). My comment #1 above states the distinction as "the BUTTONS retire, the deploy BRANCHES stay", and that is now too broad. It holds for dev and fails for demo and no.

WHY IT FAILS THERE: under the new topology demo and no are installed BY A PERSON on purpose — the operator surface is what those boxes exist to test. Nothing legitimately writes their deploy branches any more. A dormant branch plus a live deploy-to-X workflow is still a working push-to-install path, aimed precisely at the two boxes whose value depends on a human performing the install. Leaving it is not neutral: it is a standing bypass of the gate, and the first time someone is in a hurry it will be used.

The corrected rule, now in the description and as AC#4: a push-to-install path survives only where an automated install is the INTENDED behaviour. That is dev, and only dev.

MARKED AS MINE, NOT HIS. The King ruled that the master-to-X buttons retire and that demo and no become human-gated. He did not say anything about their deploy branches. This consequence follows from his own rule plus the topology, but I derived it, so it is flagged rather than presented as ratified — he can strike AC#4 in one line without disturbing anything else in the entry.
---

author: architect
created: 2026-08-19 07:39
---
UPDATED to the King's final topology. Comment #2 above says demo and no are both human-fidelity canaries; that is superseded. **Demo is out of the canary role entirely** — dev already answers the does-it-install question, so demo becomes an ordinary installation following releases on its own (STATBUS-248). **Norway is the single human canary.**

THE RULE THIS ENTRY CARRIES IS UNCHANGED BY THAT, which is the useful part: no automated push-to-install path survives for either demo or no. Only the REASON differs per box — on Norway a push bypasses the human gate; on demo it overrides the box's own channel. I sharpened the wording from "where an automated install is the intended behaviour" to "where an automated PUSH is the intended way that box gets its software", because the first phrasing would read as covering demo too: demo does install automatically, it just does it by following a channel rather than by being pushed at.

STILL MARKED AS MINE. The King ruled on the buttons and on the canary roles; the fate of the demo and Norway deploy branches follows from those rulings but he did not state it. AC#4 can be struck in one line without disturbing the rest of the entry.
---

author: foreman
created: 2026-08-19 07:50
---
KING APPROVED 2026-08-19 (presented in dialogue, one by one): the entry as written INCLUDING AC#4 (the architect-derived branch retirements for Norway and demo — not struck). Explicit reservation: "barring 248" — this approval does not pre-ratify STATBUS-248; AC#6's production-sweep leg executes only after 248 is judged on its own terms. Build may start on everything except the master-to-production/production-to-all removals, which wait for 248's verdict.
---

author: foreman
created: 2026-08-19 09:57
---
244a LANDED as 0265c8f8b (architect approved with one required doc amendment, folded and re-frozen before landing): 11 workflow files deleted (8 non-dev master-to-X, production-to-all, deploy-to-demo, deploy-to-rune-no — 543 lines removed), AGENTS.md + doc/CLOUD.md rewritten to the per-role model WITH the transitional-truth paragraph (the five country deploy-to-X remain until Wave D1's channel confirmation; the doc says so plainly, with the stranding rationale). Origin deploy branches DELETED: ops/cloud/deploy/demo, ops/standalone/deploy/rune-no. AC#2 (docs) closed; AC#1/#4/#6 close with 244b (master-to-dev, Wave C) and the Wave-D country-path deletions; AC#3 holds by construction (dev untouched, verified). master-to-dev remains the only button, by sequencing design, until 247's tag-to-dev replaces it.
---

author: foreman
created: 2026-08-19 10:40
---
244b SEQUENCING (foreman, on C1's landing): tag-to-dev now EXISTS in the landed orchestrator (4324f1d3a) but has never RUN — the next RC cut is its first live proof. master-to-dev is dev's only PROVEN deploy path until then, so its deletion holds until one cut has driven dev through the new mechanism — the same do-not-delete-the-only-receive-path-before-its-replacement-is-proven logic already ruled for the country slots (comment on 251). 244b executes immediately after the first green tag-to-dev arrival on dev.
---
<!-- COMMENTS:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Retire master-to-X buttons (landed 0265c8f8b, 2026-08-19): eight non-dev master-to-X workflows deleted, origin branches deleted for demo and rune-no, docs rewritten to per-role model with transitional-truth paragraph. AC#2 (docs) closed; AC#1/#4/#6 sequenced (244b waits for 247 proof).
<!-- SECTION:FINAL_SUMMARY:END -->
