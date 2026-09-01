---
id: STATBUS-335
title: >-
  install-reconcile-residue: users.yml edits, credential rotation, and
  healthy-box compose changes are outside install's apply guarantee
status: To Do
assignee: []
created_date: '2026-09-01 20:47'
updated_date: '2026-09-01 21:42'
labels:
  - cli
  - config
  - ops
dependencies: []
priority: low
type: enhancement
ordinal: 328000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Issue: ./sb install applies generated .env and Caddy changes (STATBUS-332), but three config artifacts remain outside its guarantee (code audit 2026-09-01):
1. .users.yml edits are never reapplied once users exist — the Users step is gated on auth.user count only (cli/cmd/install.go:998-1013), though the upsert path exists (cli/cmd/users.go:41-69).
2. Rotated .env.credentials values flow into .env and containers, but nothing re-ALTERs existing database role passwords — the box ends up semantically stale (only db restore-local reapplies passwords, cli/cmd/db.go:793-805).
3. Compose-file/build changes on a healthy box are not applied — Images and Services steps are skipped when images exist and the DB is healthy (install.go:696-697, 946-964).

Fix: extend install's reconciliation — make the Users step upsert unconditionally (it is idempotent), add a credentials-changed signal that re-ALTERs the affected roles, and rule on the healthy-box compose-change path.
No new verb: install stays the one entrypoint (the 332 principle).

Acceptance: editing .users.yml then running install updates the user in the database; rotating a credential then running install leaves the role password matching .env.credentials; each proven by a test or documented as explicitly out of scope with the refusal visible to the operator.
<!-- SECTION:DESCRIPTION:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Slice 1 (users.yml reapply) landed locally, foreman-reviewed and committed: checkUsersDone now compares .users.yml's sha256 against a marker (.users.yml.sha256, gitignored) written only after a successful users create upsert; changed file or missing marker → reconcile; absent file → no-op. Tests: marker gating (3 cases) + full cli/cmd suite green. Slices 2 (credential rotation re-ALTER) and 3 (healthy-box compose changes) remain — both need the King's ruling before build.

King (2026-09-01, retiring for the night): .users.yml is just to get started — he runs ./sb users create by hand after editing it, and that is fine. Slice 1's marker-gating is a convenience, not a correctness requirement; slices 2-3 are accordingly lower urgency and still await his ruling before any build.
<!-- SECTION:NOTES:END -->
