---
id: STATBUS-531
title: Upgrade sql_saga from v1.3 to v1.4 and verify temporal behavior
status: In Progress
assignee: []
created_date: '2026-10-27T13:45:00Z'
updated_date: '2026-10-27T13:45:00Z'
labels:
  - database
  - dependencies
  - sql-saga
dependencies: []
priority: high
type: enhancement
ordinal: 457204
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
### North Star
STATBUS runs sql_saga v1.4, with its fixes verified against our temporal merge and import workloads, and with no regression in database behavior.

### Zoom out
`postgres/Dockerfile` currently pins `sql_saga_release=v1.3`. The upstream `v1.4` tag exists at `8759b7b88`. There is no GitHub Release object, so the v1.3..v1.4 commit and schema changes are the review source. A version pin alone does not prove that our stored procedures, imports and migrations still behave correctly.

### Zoom in
- Review the upstream v1.3..v1.4 changes, including extension SQL, planner behavior and pgrx/PostgreSQL 18 compatibility, before editing the pin.
- Update `postgres/Dockerfile` to `sql_saga_release=v1.4`, and any required build or runtime definitions that the upstream release changes.
- Do not edit released STATBUS migrations to accommodate the dependency. If the upstream release requires a new migration, explain why and test both fresh installs and upgrades.
- Run the relevant sql_saga/temporal pg_regress tests and the fast suite, not just a build. Regenerate `doc/db` and generated types only if the dependency changes their outputs.

### Closing review
- **Memory:** none needed; upstream tag and test evidence are in the ticket.
- **Documentation:** record behavior changes and the upstream tag in Implementation Notes; regenerate `doc/db` only if definitions changed.
- **Cleanup:** no temporary upstream checkout in the main tree.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 The upstream v1.3..v1.4 changes are reviewed and postgres/Dockerfile pins v1.4, with behavior and compatibility notes recorded in Implementation Notes
- [ ] #2 Relevant sql_saga/temporal pg_regress tests and the fast suite pass; any upstream-required STATBUS migration is forward-only and tested on fresh install and upgrade
- [ ] #3 CI is green at the change commit, including the database image build, and generated doc/db/types are updated only if their contents changed
<!-- AC:END -->
