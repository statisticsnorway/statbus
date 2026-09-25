---
id: STATBUS-407
title: Installation and automatic updates keep database role passwords aligned with saved settings
status: In Progress
assignee: []
created_date: '2026-09-24 15:46'
updated_date: '2026-09-25 12:20'
labels:
  - release-bug
  - install
  - database
  - upgrade
  - security
dependencies: []
priority: high
type: bug
ordinal: 360000
---

## Status 2026-09-24

**In Progress.** `474cf6119`, `145c17292`: `cli/internal/dbroles/dbroles.go` / `dbroles_test.go` and `cli/internal/upgrade/role_password_sync_test.go` cover four-role reconciliation, unchanged no-op, and service ordering (#1-3 by equivalent tests). #4 `5-install-orphaned-db-volume-credentials.sh` is authored, real-VM proof pending. **Remaining:** run surviving-volume recovery on a disposable VM, preserve users, and observe API and automatic-update readiness.

Baseline: `origin/master` at `373d15fc3`. Criterion disposition and remaining positive targets are above; the acceptance criteria below remain authoritative. An authored but unrun VM scenario is **proof pending**, not met.

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
After the database is available, installation reconciles administrator, application, API, and notification role passwords through the database-local trusted connection before any password-authenticated connection. Automatic-update startup performs the same reconciliation before its authenticated connection. Matching passwords produce a verified no-op.

## Evidence, 2026-09-24

Role passwords are initially set only during empty-volume initialization (`postgres/init-db.sh:135-141,223` at master `7a9cf707e`). The disposable VM showed a surviving volume with regenerated settings, API authenticator failure, and automatic-update administrator failure (`/Users/jhf/ssb/.jcode/scratch/rest-loop.md:45-58`). The prototype reconciled all four roles locally and restored API and automatic-update readiness (`/Users/jhf/ssb/.jcode/scratch/rest-loop.md:55-67`). Password-authenticated consumers and the database-local ordering are documented at `/Users/jhf/ssb/.jcode/scratch/rest-loop.md:22-31,34-43,60-67`. How credentials diverged on the customer box remains undetermined (`/Users/jhf/ssb/.jcode/scratch/rest-loop.md:16-18`).
## rc.03 evidence and fix, 2026-09-25

rc.03 install-recovery run 36116753412, job 108013586533 (5-install-orphaned-db-volume-credentials). The LXD fork prototype (tmp/throwaway-lxd-prototype.md lines 43-46) reproduced phase b in 2 minutes: reinstall over a surviving database volume with new credentials failed step 8 in 15 s, PostgREST looping on `password authentication failed for user "authenticator"`, because `reconcilePublishedPorts` ran before `syncRolePasswords` in cli/cmd/install_services.go. Fixed in `46488ccb4` (step 8 order: DB health -> syncRolePasswords -> restart clients -> reconcilePublishedPorts -> readiness), with a source-order test and a behavioral regression (red before, green after), merged to master in `a3526f832`, first candidate carrying it: v2026.09.3-rc.05. VM proof pending on rc.05's install-recovery run.

<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 `new: cli/cmd/install_database_credentials_test.go::TestReconcileRolesBeforeAuthenticatedConnections` proves all four roles are reconciled through the local trusted connection before installer TCP authentication.
- [ ] #2 `new: cli/internal/upgrade/database_credentials_test.go::TestServiceReconcilesBeforeConnect` proves automatic-update startup reconciles the same roles after database availability and before its authenticated connection.
- [ ] #3 `new: cli/internal/databasecredentials/reconcile_test.go::TestMatchingPasswordsAreNoOp` records zero role changes when all four passwords already match.
- [ ] #4 `new: test/install-recovery/scenarios/5-install-orphaned-db-volume-credentials.sh` preserves a disposable database volume and existing users, intentionally changes settings credentials, exercises both reconciliation paths, and observes API readiness plus completed automatic-update startup.
<!-- AC:END -->
