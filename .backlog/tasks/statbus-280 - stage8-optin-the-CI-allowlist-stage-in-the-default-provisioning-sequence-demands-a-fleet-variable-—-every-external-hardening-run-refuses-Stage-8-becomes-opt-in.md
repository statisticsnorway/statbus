---
id: STATBUS-280
title: >-
  stage8-optin: the CI-allowlist stage in the default provisioning sequence
  demands a fleet variable — every external hardening run refuses; Stage 8
  becomes opt-in
status: Done
assignee:
  - mechanic
created_date: '2026-08-27 16:26'
updated_date: '2026-08-27 16:43'
labels:
  - ops
  - release-chain
dependencies: []
priority: high
type: bug
ordinal: 273000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
rc.10's smoke legs failed deterministically: vm-bootstrap.sh (:410, :464) runs the candidate's ops/setup-ubuntu-lts-24.sh full-sequence (--skip-stages=4 only); Stage 8's REQUIRED SSHDOERS_REF refusal fires on any fresh box without the fleet variable, FAILED_VERIFICATIONS exits 1, HARDENING FAILED. The real wound: every EXTERNAL OPERATOR running the documented provisioning script hits a refusal demanding a CI-fleet variable — the product-must-not-know-doors violation arriving through ops/. rc.09 predated Stage 8; rc.10's legs were the script's first full-sequence run. The smoke legs caught what three careful acceptances missed — all three ran MODIFIED invocations (stage-8-only twice, stage-3-only), none the unmodified default every real user runs.

ARCHITECT'S RULED SHAPE — Stage 8 is OPT-IN, not self-skipping: absence of SSHDOERS_REF in a default run means the stage WAS NEVER REQUESTED (the majority and correct case — almost no installation has a CI door), which is categorically different from absent-means-default (where absence is always a gap). Message states what did NOT happen and how to request it: "Stage 8 not run: no CI command door declared for this host. To install one, set SSHDOERS_REF." The refusal STAYS when the ref IS provided but something is wrong. Rejected discriminator, recorded: keying on ops/<host>/ existence — cannot check the repo without a ref. Safety: a fleet operator forgetting the ref is caught downstream by 259's own drift check ("has Stage 8 ever run there?"). HARNESS: relies on the opt-in, does NOT add skip-stages 8 — it must keep exercising the operator path.

STANDING LESSON: when a change adds a stage to a sequence, acceptance MUST include the unmodified default invocation — the only invocation with users.

Fix rides the next candidate (rc.11); acceptance = container run of the DEFAULT full sequence with no env reaching the opt-in message and exit 0 path, plus the stage-8-requested path still refusing/working as before.
<!-- SECTION:DESCRIPTION:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Landed at 339fd3120. Stage 8 is opt-in: the default provisioning sequence without SSHDOERS_REF prints "Stage 8 not run: no CI command door declared for this host. To install one, set SSHDOERS_REF." and continues clean (proven by running the unmodified default invocation in a real container — Stage 8 absent from FAILED_VERIFICATIONS; the four remaining fails are container-environment artifacts, named); the requested path is regression-free against the fourth niue session's proven behavior. The architect's category distinction recorded: a stage never requested has not defaulted to anything — absence of a CI door is the normal state of the world, unlike the channel where absence is always a gap. The harness deliberately keeps running the operator path. Standing lesson pinned: acceptance must include the unmodified default invocation — the only invocation with users.
<!-- SECTION:FINAL_SUMMARY:END -->
