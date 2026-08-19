---
id: STATBUS-251
title: >-
  new-instance-script-drift: the country-instance installer still generates the
  retired push-to-install workflows — and the new-box channel default needs a
  ruling
status: To Do
assignee: []
created_date: '2026-08-19 09:54'
labels:
  - ops
  - release
dependencies: []
references:
  - ops/create-new-statbus-installation.sh
  - doc/CLOUD.md
priority: medium
type: chore
ordinal: 244000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
STATBUS-244a retired the master-to-X and per-slot push-deploy workflows — but the script that creates a NEW country instance still generates exactly those files, so the next instance created would resurrect the retired mechanism one box at a time.

WHAT THE EVIDENCE SHOWS (mechanic, during the 244a sweep): ops/create-new-statbus-installation.sh generates master-to-<slot>.yaml and deploy-to-<slot>.yaml for each new instance. Under the approved topology (STATBUS-248 + the King's opt-in amendment), a new country instance needs NEITHER: it sits on the stable channel, is offered each promoted release, and a human performs the upgrade — zero deploy workflows, zero deploy branches.

THE FIX: the script stops generating the retired files and instead configures the new instance per its role (stable channel, opt-in). The doc/CLOUD.md runbook already carries the mechanic's inline flag at the affected steps.

SECOND ITEM, RULING NEEDED (architect or King): the new-STANDALONE-box default of UPGRADE_CHANNEL=prerelease (doc/CLOUD.md authoring) predates Norway being named the sole human canary. By 248's logic a future non-canary standalone belongs on STABLE; prerelease-by-default would silently put a customer-shaped box on candidates. Rule the default (likely: stable for everything, prerelease only by explicit canary designation) before the next standalone is created.

WHAT IS ACHIEVED: creating a new instance produces a box that matches the approved topology by construction — no retired machinery resurrected, no channel accidents.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 create-new-statbus-installation.sh no longer generates master-to-X or deploy-to-X files for new instances and instead configures the role-correct channel
- [ ] #2 The new-box channel default is ruled and encoded: stable unless explicitly designated a canary
- [ ] #3 The doc/CLOUD.md runbook steps match the script's actual behavior
<!-- AC:END -->
