---
id: STATBUS-501
title: Cloud configuration must not be applied to a standalone installation
status: To Do
assignee: []
created_date: '2026-10-13 14:24'
updated_date: '2026-10-13 14:35'
labels:
  - install
  - cloud
  - security
dependencies: []
priority: high
type: bug
ordinal: 427204
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
FOUND 2026-10-13 reviewing the Uganda prepare run, Stage 6 (User Setup devops). The same defect appears at two levels of privilege: a standalone installation is given cloud configuration, as if it were one of our own cloud boxes. (1) The CI deploy-key sources: GITHUB_DEPLOY_KEYS defaults to statisticsnorway/statbus with no cloud intent required (lines 489 and 582), STATBUS-491 gated only the PROMPT, so the value survives and the FETCH still happens in stages 6 and 7 (populate_authorized_keys is called with it, and STAGE_ENV_REQUIREMENTS demands the variable for both stages), and the URL is GitHub deploy-keys endpoint https://github.com/<org>/<repo>.keys, which is a CI-access mechanism that returns nothing for a public repository - hence the warning the operator saw. (2) The passwordless access: Stage 6 creates a devops account, gives it passwordless sudo, and installs keys fetched from OUR GitHub user and OUR repository, on a customer box. Both are the same thing: our cloud and support access model written onto a box that is not ours. NORTH STAR: with no cloud intent declared, a standalone preparation configures only what its own operator declares; no deploy-key source, no deploy-key fetch, no devops account with passwordless sudo, and no key derived from our repository. Everything cloud-shaped happens only when cloud intent is declared (--cloud or CLOUD=true).
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 With no cloud intent, no deploy-key source is set (the default is no longer our repository), no deploy keys are fetched in stages 6 or 7, and neither stage requires GITHUB_DEPLOY_KEYS. Checked by a test and by the standalone transcript showing no fetch attempt.
- [x] #2 With no cloud intent, no devops account with passwordless sudo and no GitHub-derived keys are created. Checked by the standalone path being skipped with a plain explanation, and by the test.
- [x] #3 With cloud intent declared, the question, the fetch, the devops account with passwordless sudo and its keys all still happen exactly as today. Checked by the cloud path test and transcript.
- [x] #4 The "No deploy keys returned" warning cannot appear on a standalone run. Checked by the standalone transcript.
- [ ] #5 The next real standalone preparation shows no deploy-key or CI setup at all; to be recorded in STATBUS-497 (the Uganda rerun).
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Filed 2026-10-13 on the owner playback: one defect, one ticket - cloud configuration applied to a standalone installation. Relationship: STATBUS-491 gated the question and is Done; this ticket gates the behaviour. Implementation to be done by the coordinator once the file is free (STATBUS-489 landed at 7e38edfc4; both agents idle).

Implemented 2026-10-13 by the coordinator. WHAT CHANGED: (1) GITHUB_DEPLOY_KEYS has no default any more (empty at load time); the SSB default and the question both live inside the cloud-intent branch of setup_env. (2) One helper, deploy_keys_for_this_run(), returns empty unless CLOUD=true, and all THREE populate_authorized_keys call sites use it (the 495 access gate, stage 6 devops, stage 7 service account), so no call site can install our CI keys on a box that is not ours. (3) Stage 6 is skipped without cloud intent, with a plain explanation of what it would have done and how to enable it. (4) STAGE_ENV_REQUIREMENTS no longer declares GITHUB_DEPLOY_KEYS for stages 6 or 7, so a standalone run does not have to carry the variable at all. (5) Docs: doc/CLOUD.md provisioning step now runs the script with --cloud and explains why; doc/setup-ubuntu-lts.md marks Stage 6 and the devops account cloud-only.

A REGRESSION I CAUGHT BEFORE LANDING, worth recording: no caller passed --cloud (its only introduction was 491 help text), so gating Stage 6 would have silently stopped creating devops and installing deploy keys on OUR OWN boxes (doc/CLOUD.md step 2 runs the script without it). Fixed by making the cloud provisioning step declare the intent. ops/lxd-fleet/base.sh prepares the shared validation host and is deliberately left WITHOUT --cloud: nothing in the harness relies on devops (checked), and that host is a fixture, not one of our production boxes. If it ever needs devops, it should pass the flag explicitly.

EVIDENCE: RED against HEAD -> "FAIL deploy_keys_for_this_run is not defined", rc=1. GREEN -> seven PASS lines (no cloud intent installs no deploy keys; CLOUD=false likewise; cloud intent installs the configured keys; no call site passes the raw variable; all three fetch sites use the gate; stage 7 does not require GITHUB_DEPLOY_KEYS; the devops stage is gated), rc=0. bash -n parses; the test is wired into .github/workflows/harness-selftest.yaml. Criterion 5 needs the real Uganda rerun and rides with STATBUS-497.

REFINEMENT after the owner review of this fix (2026-10-13), recorded because it corrected my own incoherence: gating the EFFECTS was not enough. The first version of the gate ANNOUNCED itself on a standalone box - it named the devops account, passwordless sudo and the SSB GitHub accounts, and told the operator to pass --cloud to enable them. That is the same leak one level softer: a customer was told our support access model exists and offered the switch. The owner called it a contradiction, and it was.

THE RULE NOW IMPLEMENTED: cloud intent decides which run this is, and cloud-only work is INVISIBLE, not announced-and-skipped. Stages 6 (devops) and 8 (CI command allowlist) return 0 from the very first line when cloud intent is absent - BEFORE their headers - so a standalone run prints nothing about them, prompts for nothing and mentions no flag. The switch lives only in --help, doc/CLOUD.md and the stage table note. There is no third state for customer-facing output: a stage is in the run or it is not.

Stage 8 was UNGATED before this and is now gated the same way: /etc/sshdoers is our inbound CI access policy, so it belongs to cloud runs. Consequence worth knowing: ops/lxd-fleet/base.sh prepares the shared validation host WITHOUT --cloud, so that host will no longer get /etc/sshdoers or the devops account. Nothing in the harness relies on either (checked: no reference to devops outside this test), and the host is a fixture; if it ever needs them, base.sh must pass --cloud explicitly.

EVIDENCE: the red half still fails at the missing helper; the green half is now TEN passes, including "stage 6 (devops) is invisible without cloud intent: the gate precedes the header / says nothing" and the same two for stage 8. bash -n parses.
<!-- SECTION:NOTES:END -->
