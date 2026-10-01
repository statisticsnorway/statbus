---
id: STATBUS-426
title: >-
  Settings restore on an established box with a damaged .env.credentials adopts
  the surviving database by reconciling regenerated secrets
status: In Progress
assignee: []
created_date: '2026-09-28 17:41'
updated_date: '2026-10-01 13:19'
labels:
  - install
dependencies: []
priority: medium
ordinal: 375200
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Found in review of the rc.16 installer fix (tmp/review-detect-env-2.md, -3.md). restoreSettingsBeforeDetect (cli/cmd/install.go) regenerates the generated .env when .env.config and .env.credentials exist and .env is missing. It checks that .env.credentials exists, not that it is complete. On an established box whose .env AND .env.credentials content were both damaged, loadOrGenerateCredentials fills missing keys with new random passwords/JWT secret, and the Services step then synchronises database role passwords to them.

**Owner ruling 2026-10-01 13:17 UTC: ADOPT.** The installer adopts the surviving database by reconciling it to the regenerated credentials — the shipped STATBUS-407 contract (scenario 5-install-orphaned-db-volume-credentials phase c) and the only sane option, since the manual recovery would be the same operations by hand. Adoption must be complete and reported:

1. Missing database passwords are generated, the surviving database's roles are ALTERed to match, and the adoption is reported plainly (what was rotated and why).
2. The JWT split found in review is fixed as part of this: checkJWTDone (install.go:1292-1306) currently checks only that auth.secrets.jwt_secret is non-empty, so after adoption the DB would keep the OLD JWT secret while PostgREST gets the new one. The check must compare the stored secret against the credentials file, and adoption must write the new secret into auth.secrets.

The earlier refuse-shaped branch (fix/426-credentials, 3f2566e22) was BLOCK-reviewed for contradicting exactly this contract and is superseded by the ruling.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 An established box with a damaged .env.credentials is adopted: new secrets generated, surviving database roles reconciled to them, auth.secrets.jwt_secret updated, and the rotation reported in plain language
- [ ] #2 checkJWTDone compares the stored JWT secret to the credentials file (not non-empty), so a split is detected and repaired rather than missed
- [ ] #3 An interrupted fresh install with a token-only .env.credentials still resumes
- [ ] #4 Tests for each case, including the STATBUS-407 phase-c adopt path running green under the fixed checkJWTDone
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Implementation shape under the adopt ruling:

- The regeneration trigger stays loadOrGenerateCredentials (config package), which fills missing keys. What changes is what happens next on an established box: the installer's database steps reconcile — ALTER ROLE ... PASSWORD for each regenerated POSTGRES_*_PASSWORD, and auth.secrets.jwt_secret set to the regenerated JWT_SECRET.
- checkJWTDone must compare the stored secret to the credentials file value. The current non-empty check (install.go:1292-1306) is the split bug: after adoption, the DB keeps the old secret while PostgREST reads the new one and every authenticated call fails.
- The rotation must be reported in the install output and the audit record (STATBUS-403's quiet audit trail): which roles/secrets were rotated and why (credentials file was damaged/incomplete).
- Fresh-install resume (token-only credentials file, no database yet) generates as today — no reconciliation, nothing to adopt.
- STATBUS-407's scenario 5-install-orphaned-db-volume-credentials phase c (rm -rf ~/statbus, volume kept, reinstall) is the shipped contract this must satisfy green; it is in the default LXD fault gate.

History: the refuse-shaped branch fix/426-credentials (3f2566e22, never merged) was BLOCK-reviewed (tmp/review-426.md) for contradicting the 407 adopt contract; superseded by the 2026-10-01 owner ruling. Its guard analysis (which keys constitute identity, exit-78 mechanics) may inform the implementation but its refusal behavior must not be kept.

2026-10-01 implementation (fix/426-adopt): the installer snapshots missing database-identity keys before the Credentials step fills them. The existing `dbroles.SyncProject` adoption path still performs the `ALTER ROLE ... PASSWORD` repairs, and now reports the affected roles plus the damaged/incomplete credentials-file reason when an actual surviving-role mismatch is repaired. Fresh-install resume still generates the keys but reports no adoption because the newly initialized database already agrees. `checkJWTDone` now compares the stored `auth.secrets.jwt_secret` value with `JWT_SECRET` from `.env.credentials`; `runLoadJWT` upserts and verifies the credential-file value, reporting a split repair and the damaged/incomplete-file reason when applicable. Added Go tests for JWT match, split detection, repair, and the password-adoption trigger. Validation: `go build ./...`, `go vet ./...`, and `go test ./cmd/... ./internal/config/...` pass; scenario 5 phase-c assertions remain compatible (the original password-repair line is preserved, and `/rpc/auth_status` now benefits from the JWT repair). The LXD scenario itself was not dispatched because this task explicitly forbids pushing, while install-recovery execution requires a pushed candidate image.
<!-- SECTION:NOTES:END -->
