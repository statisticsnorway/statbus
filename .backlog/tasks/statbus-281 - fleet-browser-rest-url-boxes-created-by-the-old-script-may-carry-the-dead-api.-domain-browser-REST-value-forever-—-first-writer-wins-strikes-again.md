---
id: STATBUS-281
title: >-
  fleet-browser-rest-url: boxes created by the old script may carry the dead
  api.<domain> browser-REST value forever — first-writer-wins strikes again
status: Done
assignee: []
created_date: '2026-08-27 16:38'
updated_date: '2026-08-27 19:39'
labels:
  - ops
  - cloud
dependencies: []
priority: medium
type: bug
ordinal: 274000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Follow-up from the DNS-split strip (landed 6a343b1b4, architect's ruling): BROWSER_REST_URL is written through gen() (config.go:379), which preserves an existing value — so the script fix reaches NEW boxes only. Every slot created by the old script may carry BROWSER_REST_URL=https://api.<domain> in .env.config forever — and with apex-only DNS, that is a dead name. Exactly the first-writer-wins mechanism that stranded the fleet's channels (STATBUS-254), one key over.

First step, one operator read per slot: grep BROWSER_REST_URL .env.config across dev/demo/et/jo/ma/tcc/ug (and rune). If stale values exist, the durable fix follows the 254 template: either the key becomes derived (it has a computed default already — config.go:362 defaultBrowserURL) or a one-time loud translation; NOT hand-edits. Not a Ukraine blocker (fresh install gets the corrected value), but check before someone reports "the app cannot reach the API" on an existing box and a day goes into it.

WHAT IS ACHIEVED: no existing box silently carries a browser-REST base URL that stopped resolving when the subdomain split died.
<!-- SECTION:DESCRIPTION:END -->

## Comments

<!-- COMMENTS:BEGIN -->
author: operator (pinned by foreman)
created: 2026-08-27 19:39
---
FLEET READ COMPLETE (2026-08-27, read-only, .env.config→.env hierarchy, all reads succeeded, zero refusals): ALL TEN BOXES CURRENT — dev https://dev.statbus.org, demo https://demo.statbus.org, tcc https://tcc.statbus.org, ma https://ma.statbus.org, ug https://ug.statbus.org/, test https://test.statbus.org/, et https://et.statbus.org/, jo https://jo.statbus.org, ua https://ua.statbus.org (born-after-fix, verified not assumed), no (rune) https://no.statbus.org. ZERO stale api.-prefixed values anywhere. The feared first-writer-wins persistence of the dead api.<domain> browser-REST value does not exist in the fleet — every box was either corrected at some point or born after the fix. No remediation step needed; the ticket closes on absence of the defect, proven by enumeration rather than assumption.
---
<!-- COMMENTS:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
The feared fleet-wide staleness does not exist: a complete read-only enumeration of all ten boxes (nine niue slots + rune) found every BROWSER_REST_URL already on the current apex form (https://<slot>.statbus.org) and zero stale api.-prefixed values — including Ukraine, verified born-after-fix rather than assumed. First-writer-wins never got the chance to preserve the dead value anywhere. Closed on proof-by-enumeration; no remediation was needed.
<!-- SECTION:FINAL_SUMMARY:END -->
