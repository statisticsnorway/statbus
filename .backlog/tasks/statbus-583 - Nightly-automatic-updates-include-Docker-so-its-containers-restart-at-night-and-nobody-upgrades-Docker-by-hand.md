---
id: STATBUS-583
title: >-
  Nightly automatic updates include Docker, so its containers restart at night
  and nobody upgrades Docker by hand
status: In Progress
assignee: []
created_date: '2026-11-06T17:22:00Z'
updated_date: '2026-11-06T17:24:00Z'
labels:
  - bug
dependencies: []
priority: high
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
- [ ] #3 On Uganda, rerunning the auto-updates stage writes the new configuration and unattended-upgrade --dry-run lists the Docker packages
- [ ] #4 Every box StatBus prepared gets the new nightly configuration once this release is out: Uganda (owner reruns), Norway's rune and niue (owner, as root), and Albania (instructions sent to Albania's operator after the release; we have no access)
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
d40af04c3 + docs. setup-auto-reboot-test.sh: red before (tmp/583-auto-updates-red.log: Docker not an allowed origin, stage silent about it), green after (tmp/583-auto-updates-green.log). Nearby setup tests pass (stage-order, summary-truth, prompt-purpose, release-matched-fetch, piped-scripts). AC3 = Uganda rerun of auto-updates with the next candidate.

Owner 2026-11-06 17:24: every box prepared with setup has had no automatic Docker updates since the script was written. Rerun the auto-updates stage as root on each: curl -fsSL https://statbus.org/setup.sh | bash -s -- --only-stages auto-updates (statbus.org/rc/setup.sh until this release is stable). Then unattended-upgrade --dry-run -d lists the Docker packages. Albania: we have no access, so the owner sends instructions once the release is out.
<!-- SECTION:NOTES:END -->
