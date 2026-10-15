---
id: STATBUS-407
title: Database role passwords always match the saved settings
status: In Progress
assignee: []
created_date: '2026-09-24 15:46'
updated_date: '2026-10-15 20:08'
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

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
### North Star
The database role passwords always match the saved settings, so the API, the app and the upgrade service can log in after any install, reinstall or restart.

### Zoom out
PostgreSQL sets role passwords only once, when an empty data volume is first initialized. The settings file can be regenerated later while the volume survives: a reinstall after deleting the installation directory, a damaged credentials file, a restore. From then on the settings and the database disagree, and every client that logs in with a password fails while the database itself looks healthy.

The settings file is the authority. So whoever is about to connect with a password first makes the database agree with it, through the database's own local socket, which needs no password. The installer does this before its first password connection, and so does the upgrade service before its first connection. When the passwords already agree nothing is changed.

### Zoom in
- **Incident, Finland 2026-09-24 (v2026.09.2):** after `statbus-local-db-data` was removed and recreated, the API logged `password authentication failed for user "authenticator"` and restart-looped (`tmp/finland-answers-4.txt:52-58`). How the operator's credentials diverged is not established. A disposable Hetzner VM reproduced the mechanism with a surviving volume and regenerated `.env.credentials`: the API failed on `authenticator` and the upgrade service on the administrator (SQLSTATE `28P01`), timing out at step 17. Role passwords are set only in `postgres/init-db.sh` (lines 135-141, 223).
- **Shipped (v2026.09.3):** `06930a2d3` adds `dbroles.Sync` (`cli/internal/dbroles/dbroles.go`), comparing each login role's SCRAM verifier with `.env` and re-applying mismatches over the local socket. `e8786019b` makes the upgrade service call it before its first connection (`syncRolePasswordsBeforeConnect`, `cli/internal/upgrade/exec.go`). `46488ccb4` moves the installer's sync before published-port reconciliation in step 8, after rc.03 showed the old order failing (`cli/cmd/install_services.go`).
- **Proof, unit:** `TestSyncIsNoOpWhenPasswordsAgree`, `TestSyncReappliesOrphanedVolumePasswords`, `TestTargetFromEnvListsEveryInitDbLoginRole`, `TestVerifierMatchesRealPostgres18` (`cli/internal/dbroles/`); `TestRunStartServicesSyncsPasswordsBeforePublishedPorts`, `TestRunStartServicesOrphanedVolumeRepairsBeforePortProbe` (`cli/cmd/install_services_test.go`); `TestDaemonSyncsRolePasswordsBeforeFirstConnect`, `TestSyncRolePasswordsBeforeConnectNeverFailsTheBoot` (`cli/internal/upgrade/role_password_sync_test.go`). All green 2026-10-15.
- **Proof, real box:** `5-install-orphaned-db-volume-credentials.sh` deletes the installation directory, keeps the volume, regenerates credentials and reinstalls. Phase c requires the install to report re-applying the passwords, rest steady, `/ready` 200, `/rpc/auth_status` 200, existing users intact and the upgrade service step completed. PASS in rc.17 LXD.
- **Not proven on a box:** the upgrade service meeting a mismatch on its own, when no installer ran first. In the scenario the installer always syncs first, so the daemon's own sync finds nothing to do. The daemon's ordering is proven only by source position.

### Closing review
- **Memory:** none needed.
- **Documentation:** none needed; the `dbroles` package comment already states the rule and why.
- **Cleanup:** none.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 The installer re-applies every login role password from the settings over the local socket before its first password connection, and changes nothing when they agree (`TestRunStartServicesSyncsPasswordsBeforePublishedPorts`, `TestSyncIsNoOpWhenPasswordsAgree`, `TestSyncReappliesOrphanedVolumePasswords`)
- [x] #2 The upgrade service does the same before its first connection, and a sync failure never stops its boot (`TestDaemonSyncsRolePasswordsBeforeFirstConnect`, `TestSyncRolePasswordsBeforeConnectNeverFailsTheBoot`)
- [x] #3 On a real box, reinstalling over a surviving volume with regenerated credentials leaves the API steady and ready, users intact and the upgrade service running (`5-install-orphaned-db-volume-credentials.sh`, rc.17 LXD PASS)
- [ ] #4 [Owner] Decide whether a real-box proof of the upgrade service repairing a password mismatch on its own (no installer first) is required, and record it in Implementation Notes. No: check this and set Done. Yes: add that scenario as a new criterion.
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
### Evidence
- **AC1-2:** green locally on master, 2026-10-15. AC2's ordering test checks call position in source, not behaviour.
- **AC3:** rc.17 LXD PASS (2026-09-29 audit, `ea170989e`); earlier phase-b PASS rc.05 run `36130286326`.
- **Superseded criteria:** the restyle named three test files that were never written (`install_database_credentials_test.go`, `upgrade/database_credentials_test.go`, `databasecredentials/reconcile_test.go`); the tests above landed instead. The stacked rc.03/rc.05/rc.08 progress notes were folded into Zoom in and AC3.
<!-- SECTION:NOTES:END -->
