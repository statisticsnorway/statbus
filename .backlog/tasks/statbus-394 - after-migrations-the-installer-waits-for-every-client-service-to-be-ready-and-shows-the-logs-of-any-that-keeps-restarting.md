---
id: STATBUS-394
title: >-
  After database setup, the installer confirms the API, application, worker, and
  automatic updates are ready
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
After database setup, the installer keeps database role passwords and generated settings in agreement, waits for the API, application, and worker to become ready, confirms the automatic update service can reach the database before enabling it, and verifies that the advertised web address answers over HTTPS when the selected certificate mode expects HTTPS. It says installation is complete only after those checks pass.

## Evidence, 2026-09-24

Primary records: `/Users/jhf/ssb/statbus/tmp/finland-transcript-actual.txt`, `/Users/jhf/ssb/statbus/tmp/finland-transcript-2-actual.txt`, `/Users/jhf/ssb/statbus/tmp/finland-chat-3.txt`, `/Users/jhf/ssb/statbus/tmp/finland-answers-4.txt`, `/Users/jhf/ssb/statbus/tmp/installer-message-audit.md`, and `/Users/jhf/ssb/statbus/tmp/setup-connection-map.md` (as applicable). Proposed behavior below is not an observation.

The Finland API restart loop reported `FATAL: password authentication failed for user "authenticator"`. An interrupted first run left the database role password and generated settings out of agreement. Step 17 then enabled automatic updates before proving its database route and timed out.

The local Multipass replay separated the observed causes. The step-17 timeout was reproduced by the port-80 path, which left the web entry point stopped and its database route unavailable. The API restart loop appeared only after deliberately making database role passwords disagree with generated settings. Certificate failure caused neither condition, but the installer still printed `Installation complete!` and an HTTPS address that could not complete a TLS handshake; TLS PostgreSQL on port 5432 failed likewise. This final HTTPS check fits this ticket's end-to-end readiness boundary, so no separate ticket is needed. Source: `/Users/jhf/ssb/statbus/tmp/local-ville-replay.md`, lines 598-605, 643-695, 697-783, 914-962, and 995-1001.

## Proving scenario

New harness scenario `5-install-rest-crashloop` injects a mismatched API database password and verifies that rerunning the one install command reconciles the role password and settings. A route check confirms the database is reachable through the automatic update service path before that service is enabled. The standalone certificate scenarios confirm that the advertised HTTPS address answers successfully before the completion message is printed.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Every installer run keeps database role passwords and generated settings in agreement.
- [ ] #2 The installer confirms the API, application, and worker are ready after database setup.
- [ ] #3 The installer confirms the database is reachable through the automatic update service route before enabling that service.
- [ ] #4 The `5-install-rest-crashloop` scenario converges through the one install command and ends with every application service ready.
- [ ] #5 When the selected certificate mode expects HTTPS, the final check confirms the advertised web address completes TLS and returns an HTTP response before printing `Installation complete!`.
<!-- AC:END -->
