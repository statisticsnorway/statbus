---
id: STATBUS-247
title: >-
  rc-tag-deploys-the-canary: point the existing deploy machinery at the
  candidate instead of at master
status: To Do
assignee: []
created_date: '2026-08-19 07:14'
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
A release candidate cannot currently be deployed as such. The buttons that deploy to our canary boxes push whatever master's tip happens to be, and master keeps moving after a candidate is cut — so the box that is supposed to prove the candidate proves something else. One of those buttons even documents the intent it cannot fulfil: its own comment says dev is the release-candidate testing ground.

WHAT ALREADY WORKS, and must not be rebuilt: the deployment layer and the verdict layer are sound. A push to a deploy branch triggers a workflow that pokes the box's upgrade service and then polls until the box has actually converged, and the convergence oracle is addressed by COMMIT — it asks whether this exact commit is installed and running, and answers with a defined set of outcomes. Both layers work correctly today and neither needs changing.

THE DETAIL: only the TRIGGER is wrong. It answers "deploy master's tip" when the question is "deploy this candidate". The deploy branches are pointers, and a pointer can point at a tag's commit just as easily as at a branch tip — nothing in the layers below cares which, because everything below is commit-addressed already.

THE FIX: tagging a candidate points the canary's deploy branch at THE TAG'S COMMIT, automatically. Layers two and three run unchanged, the box converges on the candidate's exact commit, and the promotion gate — which probes for a completed upgrade at exactly that commit — clears by construction with nobody pushing anything. The existing manual buttons stay for deliberate ad-hoc operations and leave the release path.

THREE DECISIONS, ruled here so the builder does not have to guess:

**Where the trigger lives: inside the release coordinator's chain, as a job.** One tag should have one thing reacting to it. A separate workflow watching the same tag would mean two reactors to reason about, two things to cancel when a candidate is superseded, and two places to look when it does not happen.

**Dev goes first and its failure stops the chain.** It becomes the cheapest and most realistic check we have — a real box with real data taking the real release — so it belongs ahead of the synthetic fleets, on exactly the cheapest-first, stop-on-failure logic the chain already uses. If a real box cannot take the candidate, renting 31 machines to test fixtures is waste.

**Norway goes after the fleet is green.** Dev is the testing ground and absorbs first; Norway is production-shaped and should not take a candidate the fleet has not cleared. That makes the canary graduated — dev, then Norway, then production on promotion — which is the same risk gradient the fleets already follow, and it costs minutes rather than hours because it runs once the expensive part is done.

WHY THAT HELPS: cutting a candidate becomes one act with one automatic consequence, and "the canary installed it" stops being a thing a human remembers to arrange and becomes part of what the suite means when it says green.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Tagging a candidate points the canary deploy branch at the tag's commit with no human action, through the existing deploy and convergence layers unchanged
- [ ] #2 Dev's convergence runs first in the chain and its failure stops the chain before any VM fleet is dispatched
- [ ] #3 Norway's deploy runs after the fleet is green, and its failure is reported as loudly as a fleet failure
- [ ] #4 The promotion gate finds a completed upgrade at the candidate's exact commit on both canaries, with no deploy-branch push performed by a person
- [ ] #5 The manual master-to-X buttons still work for ad-hoc operations and are documented as outside the release path
- [ ] #6 Proven end to end on a real cut: tag → dev converges → fleet → Norway converges → gate clears
<!-- AC:END -->
