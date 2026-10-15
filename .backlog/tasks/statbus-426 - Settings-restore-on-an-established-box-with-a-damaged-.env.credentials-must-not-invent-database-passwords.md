---
id: STATBUS-426
title: >-
  An installed box that lost its credentials adopts its surviving database by
  reconciling regenerated secrets
status: Done
assignee: []
created_date: '2026-09-28 17:41'
updated_date: '2026-10-15 19:40'
labels:
  - install
dependencies: []
priority: medium
ordinal: 375200
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
### North Star
When an installed box loses its credentials file but keeps its database, running the install command adopts that database: new secrets are generated, the database is brought into agreement with them, and the operator is told exactly what was rotated.

### Zoom out
The credentials file is the authority (STATBUS-407). If it is damaged or incomplete on a box whose database survives, the installer fills in the missing secrets with new random values. There are then two possible responses: refuse and make the operator repair by hand, or adopt the database by doing those same repair steps automatically. Owner ruling (2026-10-01): **adopt**, because the manual recovery would be exactly the same operations. Adoption must be complete, covering role passwords and the JWT signing secret, which the database also stores, and it must be reported in plain words. An interrupted first install, whose credentials file only ever held a token, is not a damaged box and must still resume quietly.

### Zoom in
- **Found:** in review of the rc.16 installer fix (`tmp/review-detect-env-2.md`, `-3.md`). `restoreSettingsBeforeDetect` (`cli/cmd/install.go`) checked that `.env.credentials` existed, not that it was complete. `checkJWTDone` only checked that `auth.secrets.jwt_secret` was non-empty, so after a rotation the database would keep the old JWT secret while PostgREST used the new one.
- **Rejected:** branch `fix/426-credentials` (`3f2566e22`, never merged), which refused instead; BLOCK-reviewed (`tmp/review-426.md`) for contradicting the 407 contract.
- **Shipped (merge `7c3a7ee17`, 2026-10-01, in v2026.10.1; review `tmp/review-426-adopt.md` MERGE):** the installer snapshots which identity keys were missing before Credentials fills them. `dbroles.SyncProject` repairs role passwords and reports the affected roles with the reason. `checkJWTDone` compares the stored secret with `JWT_SECRET` from the credentials file, and `runLoadJWT` writes and verifies it, reporting a split repair. A fresh database's first write is not reported as a repair.
- **Proof, unit:** `TestCheckJWTDoneComparesCredentialFileSecret_STATBUS426`, `TestRunLoadJWTRepairsSplitAndReportsAdoption_STATBUS426`, `TestRunLoadJWTReportsAbsentEmptyAndUnreadableRepair_STATBUS426`, `TestRunLoadJWTFreshDatabaseWriteIsNotReportedAsRepair_STATBUS426`, `TestPasswordReconciliationAttributionIsRoleSpecific_STATBUS426` (`cli/cmd/install_credentials_adopt_test.go`). Green 2026-10-15.
- **Proof, real box:** `5-install-orphaned-db-volume-credentials.sh` phase c plants a token-only credentials file over a surviving volume, requires `Rotated database passwords for` (or the drift line), API ready, rest steady for 60 s, and `/rpc/auth_status` 200, which needs the JWT secrets to agree. PASS in the v2026.10.1 LXD fleet `38740447079`. `5-install-interrupted-first-run.sh` (token-only file, fresh resume) PASS in the same run.

### Closing review
- **Memory:** none needed.
- **Documentation:** none needed; the installer's report is the operator text.
- **Cleanup:** none; the rejected branch no longer exists locally.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 An established box with a damaged `.env.credentials` is adopted: new secrets generated, surviving roles reconciled, `auth.secrets.jwt_secret` updated, and the rotation reported in plain words (`TestRunLoadJWTRepairsSplitAndReportsAdoption_STATBUS426`, `TestPasswordReconciliationAttributionIsRoleSpecific_STATBUS426`; phase c of `5-install-orphaned-db-volume-credentials.sh`)
- [x] #2 `checkJWTDone` compares the stored JWT secret with the credentials file, so a split is detected and repaired (`TestCheckJWTDoneComparesCredentialFileSecret_STATBUS426`)
- [x] #3 An interrupted fresh install with a token-only `.env.credentials` still resumes without reporting an adoption (`TestRunLoadJWTFreshDatabaseWriteIsNotReportedAsRepair_STATBUS426`; `5-install-interrupted-first-run.sh`)
- [x] #4 The STATBUS-407 phase-c adopt path runs green on a real box under the new check (LXD fleet `38740447079`, v2026.10.1)
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
### Evidence
- **AC1-3:** unit tests green locally on master, 2026-10-15; merge `7c3a7ee17` in v2026.10.1.
- **AC1, AC3, AC4 real box:** LXD fleet `38740447079` (v2026.10.1), `comparison.tsv`: `5-install-orphaned-db-volume-credentials PASS`, `5-install-interrupted-first-run PASS`.
<!-- SECTION:NOTES:END -->
