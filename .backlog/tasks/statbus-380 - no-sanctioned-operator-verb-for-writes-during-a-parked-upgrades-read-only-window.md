---
id: STATBUS-380
title: >-
  No sanctioned operator verb for writes during a parked upgrade's read-only
  window
status: To Do
assignee: []
created_date: '2026-09-21 12:03'
updated_date: '2026-09-21 12:03'
labels:
  - upgrade
  - recovery
  - cli
dependencies: []
references:
  - STATBUS-376
  - feae0fccf
priority: low
type: task
ordinal: 22
---

## Origin

On 2026-09-21, the owner reviewed the c-rollback-resurrection arc's fixture
repair (`feae0fccf`). The arc repairs B's intentionally broken `auth_status`
during B's parked read-only window using
`PGOPTIONS=-c default_transaction_read_only=off` via in-container admin psql.
This is the same libpq-level exemption used by the product's own maintenance,
including floor replay and post-restore fixes. The owner asked whether that is
circumventing the invariant.

## Facts

As specified in `doc/upgrade-recovery-model.md:60` and
`doc/read-only-upgrade-window.md`, the parked upgrade's read-only window is a
**client hold** at the `default_transaction_read_only` level. It is deliberately
**not** an admin capability boundary because recovery requires maintenance
writes while clients are frozen. The exemption is PostgreSQL-level: anyone
with admin credentials can write. The arc's fixture repair is therefore
consistent with the design.

A real operator repairing the root cause of a parked upgrade, the human step in
"park → repair → schedule fix release", currently has exactly two paths:

1. Use raw admin psql with the exemption. This is undocumented as an operator
   flow, easy to get wrong, and leaves no product audit trail.
2. Run `./sb install`, which un-parks the upgrade for one fresh attempt. That is
   a retry mechanism, not a way to repair data before retrying.

There is no product verb meaning "let me write deliberately while the box is
held, and record that I did".

## Design question

Should there be a sanctioned repair path, for example `./sb repair`, that opens
a narrowly scoped write session against a parked or held box, records the
action in `public.upgrade_state_log`, names the operator, and keeps clients
held? Or is the documented answer that the operator must un-park via
`./sb install` first and then repair normally?

The decision must consider:

- audit: who wrote, when, and why;
- blast radius: one statement versus a session;
- the window's purpose: protecting the frozen state for recovery, while a
  repair by definition changes what recovery restores; and
- whether the arc harness should use the sanctioned verb instead of raw DDL.

The c-rollback-resurrection arc currently sets the precedent. If a verb is
chosen, migrate the arc to it. This question is related to STATBUS-376, the
Finland install workstream, and the read-only window documentation.
