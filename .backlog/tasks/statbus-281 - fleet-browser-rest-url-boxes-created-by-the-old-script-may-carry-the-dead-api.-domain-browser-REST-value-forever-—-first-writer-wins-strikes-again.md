---
id: STATBUS-281
title: >-
  fleet-browser-rest-url: boxes created by the old script may carry the dead
  api.<domain> browser-REST value forever — first-writer-wins strikes again
status: To Do
assignee: []
created_date: '2026-08-27 16:38'
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
