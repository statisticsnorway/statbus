---
id: STATBUS-583
title: >-
  Nightly automatic updates include Docker, so its containers restart at night
  and nobody upgrades Docker by hand
status: Done
assignee: []
created_date: '2026-11-06T17:22:00Z'
updated_date: '2026-11-10T09:12:00Z'
labels:
  - bug
dependencies: []
priority: high
type: bug
ordinal: 495204
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Found on Uganda 2026-11-06: docker-ce, docker-ce-cli, docker-ce-rootless-extras and docker-compose-plugin waited as upgradable while the nightly unattended-upgrades ran. Setup's auto-updates stage allows only Ubuntu origins (distro, -security, -updates, ESM), and Docker's packages come from download.docker.com (Origin: Docker, Suite: <codename>), so they are never upgraded unless someone does it by hand. Owner 2026-11-06: nobody will do this by hand; the night window (01:00 plus up to 1h, reboot at 03:15) exists so containers can restart while nobody works. Every StatBus service is restart: unless-stopped, so a Docker restart brings them back.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 The auto-updates stage allows Docker's own repository (Docker:${distro_codename}) in Unattended-Upgrade::Allowed-Origins, and its description says Docker is updated at night too
- [x] #2 setup-auto-reboot-test.sh (or a sibling) fails against the current stage and passes after
- [x] #3 On Uganda, rerunning the auto-updates stage writes the new configuration and unattended-upgrade --dry-run lists the Docker packages
- [x] #4 The release notes and doc/DEPLOYMENT.md tell every operator, in one paragraph, to rerun the auto-updates stage as root after upgrading, with the exact command and the check that Docker is now included
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
d40af04c3 + docs. setup-auto-reboot-test.sh: red before (tmp/583-auto-updates-red.log: Docker not an allowed origin, stage silent about it), green after (tmp/583-auto-updates-green.log). Nearby setup tests pass (stage-order, summary-truth, prompt-purpose, release-matched-fetch, piped-scripts). AC3 = Uganda rerun of auto-updates with the next candidate.

Owner 2026-11-06 17:24: every box prepared with setup has had no automatic Docker updates since the script was written. Rerun the auto-updates stage as root on each: curl -fsSL https://statbus.org/setup.sh | bash -s -- --only-stages auto-updates (statbus.org/rc/setup.sh until this release is stable). Then unattended-upgrade --dry-run -d lists the Docker packages. Albania: we have no access, so the owner sends instructions once the release is out.

Owner 2026-11-06 17:24: rerunning on every box is not in our control (Albania has its own operator), so it is not a criterion. What we control is the instruction. Reruns we do ourselves are tracked as work, not as criteria: Uganda (AC3), then rune.

doc/DEPLOYMENT.md paragraph 'Servers prepared before v2026.11.1: turn on nightly Docker updates' (command + check). AC4 completes when the stable release notes carry the same paragraph.

rc.18 gate GREEN: Release Fleet Orchestrator 42290374739 for v2026.11.1-rc.18 (360b1a253); Upgrade Arc Harness 42292586368 incl. postswap-migration-ceiling success; LXD Fork Fleet 42292492037. Still open: AC3 Uganda rerun (owner), AC4 release-notes paragraph at promote.

rc.19 gate GREEN: Release Fleet Orchestrator 42369550038 (v2026.11.1-rc.19, 915220ba1).

AC4: the paragraph is in doc/DEPLOYMENT.md (auto-updates rerun with curl -fsSL https://statbus.org/setup.sh | bash -s -- --only-stages auto-updates and the unattended-upgrade --dry-run check) and was prepended to the v2026.11.1 release notes on 2026-11-07 16:38 UTC (gh release edit). AC3 is the owner's Uganda rerun (owner-only). Albania message ready in tmp/v2026.11.1-promotion-kit.md section 3.

2026-11-10 09:12 UTC owner ran on Uganda (Ubuntu 26.04 resolute, StatBus v2026.11.3): curl -fsSL https://statbus.org/setup.sh | bash -s -- --only-stages auto-updates. Stage 5 ran and verified (unattended-upgrades installed, auto-upgrades and unattended-upgrades configs, apt-daily and apt-daily-upgrade timer overrides). unattended-upgrade --dry-run -d: 'Allowed origins are: ... o=Docker,a=resolute'; 'Packages that will be upgraded: docker-ce docker-ce-cli docker-ce-rootless-extras docker-compose-plugin' (docker-ce 5:29.9.3-1~ubuntu.26.04~resolute, compose 5.7.0); 'upgrade result: True All upgrades installed'; no conffile prompts. Docker is now in the nightly updates. All criteria met.
<!-- SECTION:NOTES:END -->
