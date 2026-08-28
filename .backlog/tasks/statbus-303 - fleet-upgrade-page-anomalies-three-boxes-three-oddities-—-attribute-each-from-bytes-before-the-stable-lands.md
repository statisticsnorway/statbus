---
id: STATBUS-303
title: >-
  fleet-upgrade-page-anomalies: three boxes, three oddities — attribute each
  from bytes before the stable lands
status: In Progress
assignee:
  - '@operator'
created_date: '2026-08-28 16:24'
labels:
  - ops
  - cloud
  - upgrade
dependencies: []
priority: high
type: task
ordinal: 296000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
NORTH STAR: understand what the fleet's upgrade pages are actually doing. Three boxes show three different anomalies on the same day, and the record needs facts before fixes.

THE OBSERVATIONS (King's screenshots, 2026-08-28):
1. UKRAINE (ua): channel=stable, last checked TODAY 12:51 — yet the newest registered candidate is rc.11 (#34, registered yesterday). rc.12-rc.15 existed before that check and are absent. rc.11 shows a stuck 'release artifacts building... available when release.yaml finishes' banner though rc.11's artifacts built long ago. Born at rc.10 (post-255 git discovery, pre-291 channel filter, pre-293 CompareVersions).
2. DEMO: channel=stable, last checked 19.8 — NINE DAYS STALE. Is the check scheduler dead, erroring, or rate-limited to death? Recommended candidate rc.07 shows the gh-probe error (STATBUS-302's bug). Running v2026.07.0-rc.03 (111546ee), last install invocation 28.4.
3. A THIRD SLOT, identity unknown (Erik's screenshot): channel=stable, last checked today 11:14, offers rc.15 with short SHA 0eb4c45e and rc.14 with 00f34603 — NEITHER matches our tags' commit SHAs (rc.15=2b3862bcc, rc.14=50b13d70d). Hypothesis to verify: old-era code recorded the ANNOTATED TAG OBJECT's SHA rather than the commit SHA (our tags are signed/annotated, so the two differ) — if confirmed, that box's rows are tag-object-addressed and the canonical-commit-naming migration matters for it. Candidate row id #18572 also implies a massive registration history on that box. Identify it by matching: last install invocation 28.4.2026 16:27:56 (log 2026.04.0-rc.69), disk 153G (niue-shared).

DIAGNOSTIC SCOPE, READ-ONLY (operator collects; engineer interprets): per box (ua, demo, + identify the third from the seven niue slots): ./sb --version; last 100 upgrade-service journal lines; ./sb upgrade list tail; the check scheduler's state (systemd timer/service status); .env.config role/channel keys (grep only, no values beyond those two keys); for the third box, one row's commit_sha vs git's tag-object and commit SHAs for the same tag.

EXPECTED RESOLUTION SHAPE: most anomalies likely resolve to 'old binaries, fixed by delivery' (291 filter, 293 compare, 302's probe) — but each must be ATTRIBUTED from bytes, and anything that is NOT explained by an already-fixed bug becomes its own ticket. The stuck-at-rc.11 discovery on ua is the one that smells like it may be new.

WHAT IS ACHIEVED: every anomaly on the fleet's upgrade pages is attributed to a known fixed bug, a new ticket, or a benign explanation — before the stable promotion sends new binaries everywhere.
<!-- SECTION:DESCRIPTION:END -->
