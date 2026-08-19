---
id: STATBUS-244
title: >-
  retire-master-to-x: no path should be able to deploy an untagged commit to a
  real installation
status: To Do
assignee: []
created_date: '2026-08-19 07:10'
updated_date: '2026-08-19 07:27'
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

The distinction that matters, and the one thing not to lose: the **buttons** retire; the **deploy branches do not**. Those branches are the transport STATBUS-247's tag-driven deployment rides on — deploy-to-X listens on them, and it will keep doing so. After this they are mechanism only: written by automation, addressed at a tagged commit, never touched by a person.

THE FIX: remove the nine master-to-X workflows and the documented procedure that tells people to use them. Leave the deploy branches and the deploy-to-X workflows exactly as they are. Afterwards no master-addressed path to an installation exists anywhere — and if a deliberate ad-hoc deployment is ever needed, it must be candidate-addressed, either by scheduling a specific version on the box or by cutting one.

TWO THINGS IN THE SWEEP THAT ARE NOT LIKE THE OTHERS: master-to-production and production-to-all. Retiring them is correct for the same reason, but it leaves an open question this entry deliberately does not answer — **how a promoted stable release reaches the production slots at all**. That is a policy decision, not a mechanism gap, and it is filed separately as STATBUS-248 rather than folded in here, because the answer changes what an operator experiences on promotion day and is the King's to make.

WHY THAT HELPS: after this, the only way a version reaches an installation is by being a release someone named — so "what is running on that box, and who decided?" always has an answer, and the answer is always a tag.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 All nine master-to-X workflows are removed, and no remaining path can deploy an untagged commit to any installation
- [ ] #2 The documented deployment procedure (AGENTS.md and doc/) no longer instructs anyone to push master to a deploy branch
- [ ] #3 The deploy branches and deploy-to-X workflows are UNCHANGED and keep working as STATBUS-247's transport — written by automation, addressed at a tagged commit, never touched by a person
- [ ] #4 Any remaining deliberate version-to-box action is candidate-addressed: scheduling a named version on the box, or cutting one
- [ ] #5 master-to-production and production-to-all are removed as part of the sweep, with STATBUS-248 answering how stable reaches production before or alongside their removal
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
<!-- COMMENTS:END -->
