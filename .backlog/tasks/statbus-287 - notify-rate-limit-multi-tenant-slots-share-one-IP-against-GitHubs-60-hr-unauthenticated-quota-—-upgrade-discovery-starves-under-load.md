---
id: STATBUS-287
title: >-
  notify-rate-limit: multi-tenant slots share one IP against GitHub's 60/hr
  unauthenticated quota — upgrade discovery starves under load
status: To Do
assignee: []
created_date: '2026-08-27 17:46'
labels:
  - ops
  - cloud
  - upgrade
dependencies: []
priority: medium
type: bug
ordinal: 280000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Observed 2026-08-27 (~17:14-17:39Z, mechanic's triage of run 33099477427): "Notify cloud services" went red on 8 consecutive runs — 6 of 7 slot jobs (tcc, demo, et, ug, ma, jo) failed with GitHub's 403 "API rate limit exceeded for 162.55.61.141" from INSIDE the remote ci-notify.sh → `./sb upgrade check` call (SSH transport and sshdo all fine). 162.55.61.141 is niue's own IP, shared by every slot AND the self-hosted Actions runner; tonight's heavy CI volume exhausted the unauthenticated 60/hr per-IP quota, and each notify run then burned 6 more unauthenticated calls. statbus_dev alone succeeded ("Found 197 release tag(s)") — observed difference, cause unverified: dev presumably has an authenticated path or token the other slots lack; verify rather than assume when fixing.

Why this is a product flaw and not CI noise (the correct frame: any NSO's production cost): channel-following (STATBUS-248) makes `upgrade check` the standing discovery mechanism every box runs on its own schedule. On a multi-tenant host, N slots multiply unauthenticated polls behind one IP — the fleet's own upgrade discovery starves exactly when activity is highest. A single-tenant standalone box is unlikely to hit 60/hr alone, but the mechanism should not degrade by deployment topology.

Fix shape (verify dev's difference first): give `./sb upgrade check`'s GitHub API calls an authenticated path where a token is available — e.g. ci-notify.sh passes a GITHUB_TOKEN the way dev's path apparently already does, or the check honors a configured token from .env.credentials; authenticated quota is 5,000/hr and per-token, ending the shared-IP coupling. Secondary consideration: the notify fan-out could also stagger or batch, but auth is the principled fix — quota should attach to identity, not to whoever shares the IP.

Tonight's red is NOT release-gating (post-push fan-out only) and self-clears when the hourly window rolls; no action taken during the rc.11 cut window.

WHAT IS ACHIEVED: upgrade discovery works at any fleet density on any topology, and a busy CI evening can no longer starve the fleet's own notification path.
<!-- SECTION:DESCRIPTION:END -->
