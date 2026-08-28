---
id: STATBUS-303
title: >-
  fleet-upgrade-page-anomalies: three boxes, three oddities — attribute each
  from bytes before the stable lands
status: Done
assignee:
  - '@operator'
created_date: '2026-08-28 16:24'
updated_date: '2026-08-28 22:45'
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

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
CLOSED with a final correction on the record: the 'missing check scheduler unit' finding was a PHANTOM — the repo contains zero references to any statbus-upgrade-check unit; the product has never shipped one, and check scheduling is the upgrade service's own internal ticker + NOTIFY. Demo's nine-day staleness was the discovery failures (stale deploy-branch refspec + pre-255 API rate limiting), both since repaired. FINAL DISPOSITIONS: (1) UA — converged on its own post-HTTPS-switch, as predicted. (2) DEMO — repaired end-to-end tonight via the canonical NSO path (refspec fix → dump → checkout rc.16 → install.sh → 16/16 steps, 4 migrations, 254's channel converter announced); one residual (.env channel plumbing) being verified now, tracked to completion in this thread. (3) TCC/fleet — the tag-object SHA finding became STATBUS-304 (repair migration building tonight); the refspec landmine on five boxes became STATBUS-310. The phantom-unit lesson feeds STATBUS-308: the unit-floor detection must derive its floor from what install ACTUALLY owns, never from an assumed unit list.
<!-- SECTION:NOTES:END -->

## Comments

<!-- COMMENTS:BEGIN -->
author: operator (pinned by foreman)
created: 2026-08-28 16:29
---
COLLECTION COMPLETE, all three attributed from bytes (full detail tmp/STATBUS-303-anomalies-findings.md). (1) UKRAINE: CONVERGING — the SSH→HTTPS origin switch (from its birth-defect repairs) restored tag discovery; rc.12-15 are being discovered/registered; the stuck page was mid-convergence, no action needed, next check cycles resolve it. (2) DEMO: two defects — its discovery still fails over the old transport AND its check scheduler unit is MISSING entirely (systemctl status: not-found), which explains nine days of staleness and means demo could NEVER take the stable automatically — the silent-wedge class on the box whose whole job is to auto-follow. Operator proposes a repair (re-run install + HTTPS remote switch, mirroring Ukraine's); EXECUTION HELD — production-box mutation, King's nod required, and the exact command needs verification (the proposed --trust-github-user flag is unverified against the current CLI). (3) TCC IDENTIFIED as the third box (born 2026-04-28, v2026.04.0-rc.69) and the SHA hypothesis CONFIRMED: its upgrade rows store ANNOTATED TAG OBJECT SHAs (rc.15 row: 0eb4c45e = tag object; canonical commit: 2b3862bc) — 21k+ rows tag-object-addressed. FOREMAN CORRECTION to the report: this does not 'block STATBUS-290' (closed, unrelated — gofmt); the relevant frame is the canonical-commit-naming contract (cli/internal/upgrade/commit.go + doc/canonical-commit-naming.md). Filed separately for the architect as its own ticket. NOTE also: the report's fix-proposals are proposals — 303 was read-only by design and stays a diagnosis ticket.
---
<!-- COMMENTS:END -->
