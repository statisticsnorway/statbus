---
id: STATBUS-311
title: >-
  converted-box-channel-empty: demo on rc.16 discovers on channel none — the
  conversion path's shape breaks channel sourcing, fleet-wide at stake
status: In Progress
assignee:
  - '@engineer'
created_date: '2026-08-28 22:46'
labels:
  - upgrade
  - cli
  - config
dependencies: []
priority: high
type: bug
ordinal: 304000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
NORTH STAR: a box that declares its role must discover on its derived channel. On demo — the first CONVERTED box running rc.16 — it does not: upgrade check reports channel "" and matches nothing, which if unfixed breaks the ENTIRE fleet's discovery at exactly the moment each box converts during its stable upgrade. This must be in rc.17.

THE EVIDENCE (operator, demo, 2026-08-28 night, verbatim): .env.config carries UPGRADE_ROLE=production (channel key correctly removed by 254's one-time converter, whose announce appeared during install); .env carries the derived UPGRADE_CHANNEL=stable with its provenance comment; config generate confirms no action needed; the upgrade service restarted clean — and ./sb upgrade check still prints 'Found 202 release tag(s), none matching channel "" — nothing to register'.

THE DISCRIMINATING CONTRAST: Ghana, born fresh at the same rc.16 with the same role-only .env.config, discovers correctly ('8 stable candidates'). An arc box journal the same evening showed a NON-empty channel ('0 match channel "local"'). So the plumbing works on some paths and returns empty on demo's — the suspects: the CLI check's channel sourcing differing from the daemon's; a converted-box config shape (role in .env.config + derived key in .env + the converter's comment line) parsed differently than a born-fresh one; or an ordering issue where the check reads before derivation.

FIRST STEPS (engineer): reproduce locally — construct demo's exact file shapes (.env.config role-only; .env with the comment line + derived key) and run the current binary's upgrade check; trace where RunCheck sources the channel; find why demo's shape yields ""; fix with a test pinning the converted-box shape specifically (born-fresh is already covered by Ghana's living proof — the converted shape is the one that slipped).

WHY RELEASE-CRITICAL: all six July-era slots CONVERT when they take the stable. If converted boxes discover on channel "", every box goes dark for future releases immediately after its first successful channel-following upgrade — the fleet's second stable would reach nobody.

WHAT IS ACHIEVED: converted and born-fresh boxes discover identically, and the fleet's first stable is not also its last.
<!-- SECTION:DESCRIPTION:END -->
