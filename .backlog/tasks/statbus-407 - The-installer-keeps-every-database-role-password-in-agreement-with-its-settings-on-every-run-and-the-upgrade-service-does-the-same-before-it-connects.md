---
id: STATBUS-407
title: Installation and automatic updates keep database role passwords aligned with saved settings
status: To Do
assignee: []
created_date: '2026-09-24 15:46'
updated_date: '2026-09-24 18:44'
labels:
  - install
  - database
  - upgrade
  - security
dependencies: []
priority: high
type: bug
ordinal: 360000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
After the database is available, installation reconciles administrator, application, API, and notification role passwords through the database-local trusted connection before any password-authenticated connection. Automatic-update startup performs the same reconciliation before its authenticated connection. Matching passwords produce a verified no-op.

## Evidence, 2026-09-24

Role passwords are initially set only during empty-volume initialization (`postgres/init-db.sh:135-141,223` at master `7a9cf707e`). The disposable VM showed a surviving volume with regenerated settings, API authenticator failure, and automatic-update administrator failure (`/Users/jhf/ssb/.jcode/scratch/rest-loop.md:45-58`). The prototype reconciled all four roles locally and restored API and automatic-update readiness (`/Users/jhf/ssb/.jcode/scratch/rest-loop.md:55-67`). Password-authenticated consumers and the database-local ordering are documented at `/Users/jhf/ssb/.jcode/scratch/rest-loop.md:22-31,34-43,60-67`. How credentials diverged on the customer box remains undetermined (`/Users/jhf/ssb/.jcode/scratch/rest-loop.md:16-18`).
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 `new: cli/cmd/install_database_credentials_test.go::TestReconcileRolesBeforeAuthenticatedConnections` proves all four roles are reconciled through the local trusted connection before installer TCP authentication.
- [ ] #2 `new: cli/internal/upgrade/database_credentials_test.go::TestServiceReconcilesBeforeConnect` proves automatic-update startup reconciles the same roles after database availability and before its authenticated connection.
- [ ] #3 `new: cli/internal/databasecredentials/reconcile_test.go::TestMatchingPasswordsAreNoOp` records zero role changes when all four passwords already match.
- [ ] #4 `new: test/install-recovery/scenarios/5-install-orphaned-db-volume-credentials.sh` preserves a disposable database volume and existing users, intentionally changes settings credentials, exercises both reconciliation paths, and observes API readiness plus completed automatic-update startup.
<!-- AC:END -->
