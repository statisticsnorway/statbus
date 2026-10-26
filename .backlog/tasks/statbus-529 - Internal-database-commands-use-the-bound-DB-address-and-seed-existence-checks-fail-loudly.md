---
id: STATBUS-529
title: >-
  Internal database commands use the bound DB address, and seed existence checks
  fail loudly
status: In Progress
assignee: []
created_date: '2026-10-26 20:48'
updated_date: '2026-10-26 21:33'
labels:
  - cli
  - dev
  - release
  - database
dependencies: []
priority: high
type: bug
ordinal: 455204
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
### North Star
Development and release-preparation database commands connect to the address the database route actually binds. A public site name never decides an internal database connection, and a failed existence check never looks like an absent database.

### Zoom out
AGENTS.md explicitly requires internal clients to use the bind address and port. A site name is for users and certificates; it is not a database endpoint. An existence query has three outcomes (present, absent, unreachable), not two.

The first failure was then misreported: `delete-seed` appended `0` after any `./sb psql` failure and printed that `statbus_seed` did not exist. The following create failed because the database did exist. This hid the connection problem and wasted the release-preparation run.

### Zoom in
- Reproduced 2026-10-26 in `statbus_test`: `dev.sh postgres-variables` used `SITE_DOMAIN=test.statbus.org` as PGHOST, which did not resolve on the Mac. `.env` correctly had `CADDY_DB_BIND_ADDRESS=127.0.0.1` and `CADDY_DB_PORT=3034`.
- `dev.sh postgres-variables` must use `CADDY_DB_BIND_ADDRESS`; `sb config show --postgres` (`cli/cmd/config.go:showPostgresVars`) has the same `SITE_DOMAIN` mistake and must follow the same rule.
- `delete-seed` must distinguish a successful query returning no row from a query/connection failure. On failure it exits non-zero and prints the connection error; it does not print "nothing to delete" and does not continue to create.
- Evidence: `tmp/rc-migrate-and-test.log` and `tmp/rc-recreate-seed.log` in `statbus_test`, 2026-10-26. No `/etc/hosts` change: that would hide the product bug on one machine.

### Closing review
- **Memory:** none; the existing rule in AGENTS.md is sufficient.
- **Documentation:** the definition comments state the internal-address rule and the fail-loud existence check.
- **Cleanup:** no host-file or machine-specific workaround.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 With SITE_DOMAIN set to an unresolvable name and CADDY_DB_BIND_ADDRESS=127.0.0.1, both dev.sh postgres-variables and sb config show --postgres export PGHOST=127.0.0.1; regression tests prove both
- [x] #2 A connection/query failure during delete-seed's existence check exits non-zero with the connection error, does not claim the seed is absent, and does not proceed to create; a regression test proves the outcome
- [ ] #3 ./dev.sh migrate-and-test fast completes in statbus_test without a hosts-file workaround, and release preflight reaches the remaining gates; CI is green at the fix commit
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
2026-10-26 fix (statbus_test): dev.sh postgres-variables and sb config show --postgres now export PGHOST from CADDY_DB_BIND_ADDRESS; delete-seed's existence check exits non-zero with the psql error and only treats a successful empty result as absent. Regression tests RED against HEAD (PGHOST=unresolvable.statbus.invalid; delete-seed exit 0 + 'nothing to delete' after a failed query), GREEN with the fix: test/dev-postgres-variables-test.sh, test/dev-delete-seed-test.sh (both wired into dev.sh test-harness), cli/cmd/config_postgres_vars_test.go. go test ./cmd/ and bash -n pass. Evidence logs: tmp/test-529-{red,green}-*.log.
<!-- SECTION:NOTES:END -->
