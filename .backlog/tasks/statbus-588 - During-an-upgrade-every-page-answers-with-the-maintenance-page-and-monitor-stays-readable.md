---
id: STATBUS-588
title: >-
  During an upgrade every page answers with the maintenance page, and /monitor
  stays readable
status: In Progress
assignee: []
created_date: '2026-11-07T12:37:00Z'
updated_date: '2026-11-07T15:10:00Z'
labels:
  - caddy
  - upgrade
dependencies: []
priority: high
ordinal: 500204
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
### North Star
While an upgrade runs, every visitor sees the maintenance page (503), and the public health reading at /monitor stays available, so people know why the site is busy and monitoring keeps working.

### Zoom in
Found by the STATBUS-541 AC4 check on the rc.18 manual box (2026-11-07, tmp/541-maint-diag.log): with ~/statbus-maintenance/active present (and visible in the proxy at /statbus-maintenance/active), / answered 307 and /login 200 instead of the 503 maintenance page. /monitor itself behaved: 200 in maintenance, 503 with the critical marker.

Cause: the standalone and private Caddyfile matchers read `file /statbus-maintenance/active`. Caddy resolves a file matcher against the site root (the working directory /srv), so it looked for /srv/statbus-maintenance/active and never matched. Prototype with the box's proxy image (tmp/541-maint-prototype.log): the current form answers 200 with the marker; `file { root /statbus-maintenance; try_files /active }` answers 503 with it and 200 without.

Nothing in the automated runs fetched a page during maintenance or fetched /monitor at all, so this was never seen.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 The standalone and private Caddy templates match the maintenance marker at /statbus-maintenance/active itself (config test renders the templates and runs the matcher form; red before, green after)
- [x] #2 On a real installation, with the marker present, / and /login answer 503 with the maintenance page and /monitor answers 200; without it they answer normally (observed on the manual box)
- [ ] #3 The LXD happy-upgrade scenario fetches /monitor before, during and after the upgrade (200) and / during it (503 maintenance page), so every gate proves both
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Red: test/caddy-maintenance-route-test.sh (real caddy:2 on each template's @maintenance block) failed for standalone and private: marker present, / and /login answered 200 (tmp/588-red.log; 726343150). Fix d09f06ced: file { root /statbus-maintenance; try_files /active }. Green 13/13 (tmp/588-green.log); runs in Harness Selftest. AC2 on the rc.18 manual box (tmp/588-box-check.log): with the fixed matcher in the running proxy, no marker: / 307, /login 200, /monitor 200; marker: / 503 (maintenance page), /login 503, /monitor 200 status ok; removed: normal again; original config restored.

rc.21 gate (Upgrade Arc Harness 42380900182) failed on postswap-severed-proxy-refusal and postswap-stopped-proxy-recovery: once Caddy served the maintenance page, the post-swap self-heal completion in resumeNewSb exposed that it never removed ~/statbus-maintenance/active. Install's advertised-site check got 503. Red test 4eadb18c9 (TestPostSwapSelfHealCompletionRequiresCleanFinishing), fix 5a119f49e. rc.22 cut in progress.
<!-- SECTION:NOTES:END -->
