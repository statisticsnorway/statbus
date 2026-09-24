---
id: STATBUS-388
title: >-
  When a database step cannot connect, the installer names the unavailable route
  and the service that provides it
status: To Do
assignee: []
created_date: '2026-09-24 16:42'
updated_date: '2026-09-24 15:35'
labels:
  - install
dependencies: []
priority: high
type: bug
ordinal: 1
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Every database step either connects inside the database service or confirms that its required route is ready first. A connection failure names the unavailable route and the service that provides it in plain operator language.

## Evidence, 2026-09-24

Primary records: `/Users/jhf/ssb/statbus/tmp/finland-transcript-actual.txt`, `/Users/jhf/ssb/statbus/tmp/finland-transcript-2-actual.txt`, `/Users/jhf/ssb/statbus/tmp/finland-chat-3.txt`, `/Users/jhf/ssb/statbus/tmp/finland-answers-4.txt`, `/Users/jhf/ssb/statbus/tmp/installer-message-audit.md`, and `/Users/jhf/ssb/statbus/tmp/setup-connection-map.md` (as applicable). Proposed behavior below is not an observation.

Finland migrations dialled `127.0.0.1:5431` after the web entry point had failed to start. The visible error looked like a database failure although the database itself was healthy.

## Proving scenario

During an install-recovery run, stop the service that provides the database route before migrations. The installer either completes migrations through the database service or reports that the web entry point is unavailable and restores it on rerun.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Each database step has a reachable route before it begins.
- [ ] #2 A route failure names the address and the plain-language service that provides it.
- [ ] #3 A rerun restores the route and completes the database step.
<!-- AC:END -->

## Review correction 2026-09-24

Ground the observed host-route failure in the exact Finland transcript. Master publishes the database route at `caddy/docker-compose.yml:15`; migration connection use is at `cli/cmd/install.go:2557-2559,2889`. Add **new** `test/install-recovery/scenarios/5-install-database-route-interrupted.sh`, which observes either successful in-database migration or a plain failure naming the route/provider, followed by a successful rerun. This ticket diagnoses the route; STATBUS-390 owns transport consistency.
