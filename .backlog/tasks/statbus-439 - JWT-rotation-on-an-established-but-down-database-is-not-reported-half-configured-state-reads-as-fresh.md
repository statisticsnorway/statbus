---
id: STATBUS-439
title: >-
  JWT rotation on an established-but-down database is not reported
  (half-configured state reads as fresh)
status: In Progress
assignee: []
created_date: ''
updated_date: '2026-10-20 11:28'
labels: []
dependencies: []
priority: medium
---

## Issue

When an established box's database is DOWN at `./sb install` time (containers
stopped, volume surviving — exactly the orphaned-volume shape), install state
detection classifies the box `StateHalfConfigured`, and
`installStateHasFreshDatabase` (cli/cmd/install.go:3018) counts HalfConfigured
as a fresh database. `runLoadJWT` therefore sets `freshDatabaseBeforeInstall =
true` and skips the rotation report even though it rotated an ESTABLISHED
database's `auth.secrets.jwt_secret` to the regenerated `JWT_SECRET` —
invalidating every outstanding session token without a word to the operator.

## Evidence

rc.07 fleet run 36931112001, scenario 5-install-orphaned-db-volume-credentials
phase c: the surviving volume's JWT secret was rotated (the planted
GITHUB_TOKEN-only .env.credentials forced regeneration), `[15/18] JWT secret
RUNNING→DONE` printed with no report line, while the password reconciliation
in the same run correctly reported its rotation. STATBUS-426's contract:
"freshDatabaseBeforeInstall distinguishes the expected first JWT write on a new
database from a repair to an established database. The latter must always be
reported, including absent, empty, and initially unreadable state." An
established-but-down database is not a fresh database; the state probe just
couldn't reach it.

## Principled fix

`freshDatabaseBeforeInstall` must not be derived from reachability-based state
alone. When the database is unreachable at detect time but a database VOLUME
for this project exists (or the box has an upgrade-table/program record), the
box is established and the JWT repair must be reported. The hard reconcile
itself already works (write + verify); only the report is suppressed.

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
### Investigation 2026-10-20 (no code changed)
- **Mechanism, confirmed in code:** `runLoadJWT` (cli/cmd/install.go ~3150) reports a repair only when `!freshDatabaseBeforeInstall`. That flag comes from `installStateHasFreshDatabase(state)`, which is true for StateFresh, StateHalfConfigured and StateFreshDBIncomplete. DetectWith (cli/internal/install/state.go) returns StateHalfConfigured as soon as .env.credentials is missing, before it ever looks at the database. And StateFresh as soon as .env.config is missing. So in the orphaned-volume shape (~/statbus deleted, the db volume kept, install.sh run again), the state says 'fresh' while the volume holds an established database with its own jwt_secret.
- **Password repair in the same run reports correctly,** because it does not consult the state: it compares the live roles with .env.credentials and attributes by missingCredentialKeysBeforeInstall.
- **Fact for the fix:** a database built by migrations or the seed has no auth.secrets jwt_secret row before the JWT step (checked: statbus_seed has none). The surviving volume's database does.
- **Fix options:**
  1. **Volume-existence signal (the ticket's proposal):** record, before any compose up, whether `<COMPOSE_INSTANCE_NAME>-db-data` already existed. When it did, the database is established unless the state is StateFreshDBIncomplete (this installer's own unfinished setup). Keeps the 426 contract: absent, empty and unreadable are all reported on an established db.
  2. **Content signal:** an established database is one whose jwt_secret row existed before the JWT step. Simpler, but it would not report a deleted row on an established db, which 426 explicitly requires.
- **Recommendation:** option 1, with the probe in DetectWith's caller and a unit test driving runLoadJWT with state HalfConfigured plus an existing volume (red today), and the LXD scenario 5-install-orphaned-db-volume-credentials asserting the JWT report line in phase c.
<!-- SECTION:NOTES:END -->
