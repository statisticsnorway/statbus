---
id: STATBUS-439
title: JWT rotation on an established-but-down database is not reported (half-configured state reads as fresh)
status: To Do
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
