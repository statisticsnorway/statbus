---
id: STATBUS-253
title: >-
  deploy-key-consumer-audit: a repo deploy key installed on every country box
  may have no remaining consumer — enumerate what actually uses it, then rule
status: To Do
assignee: []
created_date: '2026-08-19 10:27'
labels:
  - ops
  - security
dependencies: []
priority: medium
type: chore
ordinal: 246000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
The instance-creation script installs GitHub-sourced public keys into each country box's authorized_keys (GITHUB_DEPLOY_KEYS). The stated purpose — "gives the deploy-to-* workflow ssh ability" — is gone: under the approved topology a country slot has no deploy-to workflow, and the canary gate SSHes with the operator's own key, not a repo deploy key. If nothing else consumes it, this is a standing CI credential on live NSO production installations with nothing that uses it.

FILED FROM the architect's 251 review (his own named miss): the design's orphan check asked whether the script creates GitHub-side objects and answered "checked, none" — the wrong question. The right question is whether the authorized_keys entry installed ON THE BOX still has a consumer.

NOT ESTABLISHED: that the key is dead. There may be a consumer not yet found — which is why this is an enumeration-then-ruling, not a removal order. "An unnecessary standing credential on a production statistical office box" gets one deliberate answer, never inheritance by default.

DISTINCT AND UNAFFECTED: runbook step 6's "Generate SSH deployment key for GitHub" — that is the box's own key for cloning the private repo, legitimate and out of scope.

THE WORK: enumerate every consumer of the GITHUB_DEPLOY_KEYS-installed authorized_keys entries — CI workflows that ssh to slots, ops scripts, the upgrade service's own paths, anything in .github/ and ops/ that authenticates to a box. Deliverable: the enumeration pinned here with each consumer named (or "none found, searched X/Y/Z"), then the architect rules keep-or-remove. Any removal ships via the ruled mechanism, never a manual write.
<!-- SECTION:DESCRIPTION:END -->
