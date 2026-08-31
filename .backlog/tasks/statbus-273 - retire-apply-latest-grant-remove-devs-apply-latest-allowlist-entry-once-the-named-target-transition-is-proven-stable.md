---
id: STATBUS-273
title: >-
  retire-apply-latest-grant: remove dev's apply-latest allowlist entry once the
  named-target transition is proven stable
status: In Progress
assignee:
  - '@operator'
created_date: '2026-08-27 13:23'
updated_date: '2026-08-31 19:44'
labels:
  - ops
  - security
dependencies: []
priority: low
type: chore
ordinal: 266000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Deferred from STATBUS-259's endgame (architect's sequencing rule b): dev's apply-latest grant in ops/niue/sshdoers deliberately COEXISTS with the new named-target apply entry through the transition, so a deploy-to-dev.yaml revert cannot strand the canary with no apply door. Once the named-target path has proven itself over real cuts (rc.10's chain run at minimum, ideally a few), remove the apply-latest entry as its own reviewed commit + Stage 8 re-run. Demo's apply-latest entry is PERMANENT (correct verb for a channel-following box) — do not touch it. Least-privilege payoff: dev's door then permits exactly one verb shape, commit-addressed.
<!-- SECTION:DESCRIPTION:END -->
