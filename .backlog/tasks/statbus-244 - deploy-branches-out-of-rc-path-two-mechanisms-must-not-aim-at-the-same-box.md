---
id: STATBUS-244
title: 'deploy-branches-out-of-rc-path: two mechanisms must not aim at the same box'
status: To Do
assignee: []
created_date: '2026-08-19 07:10'
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
Once the canary boxes install release candidates on their own, the branch-push deployment must stop aiming at them. Two mechanisms driving the same box is worse than either alone: they disagree about what should be installed, and the box obeys whichever spoke last.

WHAT GOES WRONG if this is skipped: the canaries would follow the candidate on their own tick, while a deploy-branch push could still shove master's tip at them at any moment — including the exact moment the gate is probing. The result is a box whose installed version depends on timing, and a promotion gate reading a row nobody can explain. This is the failure that already happened once, and adding the automatic path without removing the manual one makes it more likely rather than less.

THE DETAIL: the branch-as-pointer flow (push master to `ops/cloud/deploy/dev` or `ops/standalone/deploy/rune-no`, which triggers the matching deploy workflow, which triggers the upgrade service) predates the product's own channel mechanism. It deploys a BRANCH TIP, so it structurally cannot deploy a tag, which is why it drifts from the candidate the moment anything lands after a cut. It remains genuinely useful for out-of-band operations — putting a specific commit on a specific host deliberately — and nothing here proposes deleting it.

THE FIX: take the canary slots out of the release-candidate path. No automation pushes their deploy branches on a cut, and the published procedure for cutting a candidate stops mentioning them. The branches stay available for deliberate ad-hoc operations, documented as such — with a warning that using one on a canary slot overrides what that box's channel would have installed, and will therefore confuse the promotion gate until the next tick reconciles it.

WHY THAT HELPS: one box, one source of truth about what should be running on it. After this, "why is that version on dev?" has exactly one answer — its channel said so — instead of two candidate answers a human has to distinguish under time pressure.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 No automation pushes a canary slot's deploy branch as part of cutting a release candidate
- [ ] #2 The documented cut procedure no longer instructs anyone to push a deploy branch for the canaries
- [ ] #3 The deploy-branch flow remains available for deliberate ad-hoc operations, documented with the warning that it overrides the box's channel
- [ ] #4 Verified on a real cut: the canary's installed version is the candidate, and no deploy-branch run fired for those slots
<!-- AC:END -->
