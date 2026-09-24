---
id: STATBUS-407
title: >-
  The installer keeps every database role password in agreement with its
  settings on every run, and the upgrade service does the same before it
  connects
status: To Do
assignee: []
created_date: '2026-09-24 15:46'
labels:
  - install
  - database
  - upgrade
  - security
dependencies: []
references:
  - /Users/jhf/ssb/.jcode/scratch/rest-loop.md
priority: high
type: bug
ordinal: 360000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Every installer run reconciles the database passwords for the administrator, application, API, and notification roles with the generated settings before any password-authenticated connection begins. The automatic update service performs the same reconciliation after the database is available and before it connects. A healthy box verifies the passwords and continues without changing them.

## Evidence, 2026-09-24

Primary records: `/Users/jhf/ssb/statbus/tmp/finland-transcript-2-actual.txt`, `/Users/jhf/ssb/statbus/tmp/finland-chat-3.txt`, `/Users/jhf/ssb/statbus/tmp/finland-answers-4.txt`, `/Users/jhf/ssb/statbus/tmp/installer-message-audit.md`, `/Users/jhf/ssb/statbus/tmp/setup-connection-map.md`, and `/Users/jhf/ssb/.jcode/scratch/rest-loop.md` (as applicable). Proposed behavior below is not an observation.

A Hetzner Ubuntu 26.04 VM reproduced a surviving `statbus-<code>-db-data` volume with regenerated `.env.credentials`. `postgres/init-db.sh:135`, `:141`, and `:223` set role passwords only during first database initialization. The API then reported `FATAL: password authentication failed for user "authenticator"`; the automatic update service received SQLSTATE `28P01` for the administrator and timed out at step 17. Installer steps 1-16 appeared green because their database commands ran inside the database service through local trust. A prototype that reapplied all four passwords from the generated settings restored API readiness and automatic updates on the same VM.

## Proving scenario

New install-recovery scenario `5-install-orphaned-db-volume-credentials`: retain the database volume, recreate the installation directory and generated credentials, then run the one install command. Assert that installation exits successfully, API restart count remains stable for 60 seconds, the API readiness endpoint and `auth_status` return 200, the automatic update service is active, the upgrade row completes, and existing users remain intact.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Every installer run verifies and reconciles the administrator, application, API, and notification role passwords with the generated settings.
- [ ] #2 Password reconciliation runs through the database local connection before any password-authenticated installer connection.
- [ ] #3 The automatic update service reconciles the same role passwords after the database is available and before it connects.
- [ ] #4 A healthy box verifies matching passwords and continues without changing them.
- [ ] #5 The `5-install-orphaned-db-volume-credentials` scenario completes with the API ready, automatic updates active, the upgrade completed, and existing users intact.
<!-- AC:END -->

## Review correction 2026-09-24

Role anchors remain `postgres/init-db.sh:135,141,223`. Tie VM observations and the prototype to exact `/Users/jhf/ssb/.jcode/scratch/rest-loop.md` lines, and cite password-authenticated upgrade connection plus local reconciliation ordering. Add **new** `test/install-recovery/scenarios/5-install-orphaned-db-volume-credentials.sh`: on a disposable VM it preserves the database volume and existing users, intentionally changes settings credentials, exercises installer and automatic-update reconciliation, proves a matching-password no-op, then proves API and upgrade readiness. Implementation ownership is shared with STATBUS-394.
