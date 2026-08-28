---
id: STATBUS-287
title: >-
  notify-rate-limit: six slots still run pre-255 binaries that poll the deleted
  GitHub API path — resolves when the fleet takes the stable
status: In Progress
assignee:
  - '@operator'
created_date: '2026-08-27 17:46'
updated_date: '2026-08-28 09:44'
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
NORTH STAR: upgrade discovery must work at any fleet density on any topology — a busy CI evening must never be able to starve the fleet's own notification path. Since STATBUS-255 the current code achieves this by construction: discovery is a pure `git fetch --tags`, zero HTTP, no API quota to exhaust. This ticket is not a code change — it is the observation that six boxes have not received that code yet, and the record of what their reds mean until they do.

WHAT WAS OBSERVED (2026-08-27 ~17:14-17:39Z): "Notify cloud services" red on 8 consecutive runs — six of seven slot jobs (tcc, demo, et, jo, ma, ug) failing with GitHub's 403 rate-limit for 162.55.61.141 (niue's shared IP) from inside the remote `./sb upgrade check`. Only dev succeeded.

ROOT CAUSE, VERIFIED EMPIRICALLY (comment #1, `./sb --version` on all seven slots): the six failing slots all run the identical month-old binary — v2026.07.0-rc.03, commit 111546ee, built 2026-07-13 — which predates STATBUS-255's deletion of the GitHub API discovery path (c4ba87464, 2026-08-19). Their RunCheck still calls the deleted FetchReleases() against api.github.com, subject to the 60/hr per-IP unauthenticated quota that every slot and the self-hosted runner share. Dev succeeds because its binary is post-255. The error-format fingerprint matches the DELETED function exactly. The originally-assumed fix (token plumbing) is dissolved: current code makes zero GitHub API calls, so there is nothing to authenticate.

THE REMEDY IS DELIVERY, NOT CODE: current code reaching the six boxes — precisely STATBUS-248's channel-following path. They take the next promoted stable, whose binary carries 255, and the quota coupling ceases to exist on those boxes.

UNTIL THEN: notify fan-out reds on these six slots are EXPECTED and attributed — not new bugs, never gate-relevant (the notify leg is post-push fan-out only), and self-clearing whenever the hourly quota window rolls.

CLOSES WHEN: the fleet's binaries are post-255 and a notify run comes back green with no token changes anywhere.
<!-- SECTION:DESCRIPTION:END -->

## Comments

<!-- COMMENTS:BEGIN -->
author: mechanic (pinned by foreman)
created: 2026-08-27 19:45
---
ROOT CAUSE VERIFIED EMPIRICALLY (2026-08-27, ./sb --version on all seven slots) — AND IT DISSOLVES THIS TICKET'S ASSUMED FIX: no token is needed, because CURRENT code makes zero GitHub API calls. The six failing slots (tcc, demo, jo, ma, et, ug) all run the IDENTICAL month-old binary — v2026.07.0-rc.03, commit 111546ee, built 2026-07-13 — which predates STATBUS-255's deletion of the GitHub API discovery path (c4ba87464, 2026-08-19). Their RunCheck still calls the deleted FetchReleases() against api.github.com — subject to the 60/hr per-IP unauthenticated limit. Dev succeeds because its binary (rc.09, post-255) uses DiscoverTagsViaGit — pure git fetch --tags, zero HTTP, works without any token by design. Error-format fingerprint confirms it: the failing jobs' 'GitHub API returned 403: {json}' matches the DELETED function's format exactly; current code's format differs. RE-SCOPE: no code change to RunCheck, no token plumbing — the remedy is current code reaching the six boxes, which is precisely STATBUS-248's delivery path (they take the stable promoted from rc.11, whose binary carries 255). Until then, notify fan-out reds on these six slots are EXPECTED and attributed — not new bugs, not gate-relevant. CLOSES when the fleet's binaries are post-255 and a notify run comes back green without token changes.
---

author: foreman
created: 2026-08-28 09:40
---
SCHEDULED (King-directed): assigned to @operator, trigger = the fleet taking the first post-255 stable (the 271 proving sequence: rc.15 chain green → Norway human canary → promotion → channel-following delivers to the six slots). VERIFICATION PROCEDURE for whoever executes it, so no re-derivation is needed then: (1) `ssh statbus_<slot> 'cd statbus && ./sb --version'` on all seven slots — expect every binary post-c4ba87464 (2026-08-19, the 255 deletion); (2) confirm the next 'Notify cloud services' run is green on all seven slot jobs with ZERO token changes anywhere — green-without-auth is the proof that discovery is now pure git and the quota coupling is gone; (3) pin both results here and close. If any slot still fails notify AFTER carrying a post-255 binary, that is a NEW bug — different fingerprint expected — and gets its own ticket, not this one reopened. Foreman dispatches the operator when the trigger fires; until then this ticket correctly sits as an attributed wait, and notify reds on the six slots remain expected and non-gating.
---
<!-- COMMENTS:END -->
