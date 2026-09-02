---
id: STATBUS-335
title: >-
  entry-way-files: .env.credentials and .users.yml are documented entry points,
  never auto-propagated — revert slice 1, add headers
status: To Do
assignee: []
created_date: '2026-09-01 20:47'
updated_date: '2026-09-02 09:14'
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
KING'S RULING 2026-09-02 (supersedes the original fix direction): .env.credentials and .users.yml are ENTRY-WAY files — generate-once identity/seed inputs — not live configuration. No automatic propagation of either. The 332 apply machinery keeps only what it proved: generated .env and Caddy outputs.

1. REVERT slice 1 (landed 2026-09-01: sha256 marker + content-gated Users step in checkUsersDone, cli/cmd/install.go + install_users_reconcile_test.go + .gitignore line). Users step returns to its original users-exist gate. Editing .users.yml then running ./sb users create BY HAND remains the workflow.
2. HEADER in .env.credentials (written by the generator that creates the file, cli/internal/config/): a running system never reads this file back; editing it changes nothing and leaves the file mismatched with the database. To apply a changed value: delete and recreate the ENTIRE environment (destructive — all data lost; ./dev.sh recreate-database on dev, full reinstall on a production box), or apply the specific change manually with the proper commands (a support operation). The file's purpose is stable identity: recreates and restores get the same credentials back.
3. HEADER in .users.yml (written wherever the template/file is created): seed users for first install; afterwards users are managed in the application; editing this file does nothing by itself — run ./sb users create to apply ADDITIONS; existing users are not updated from this file.
4. Compose-file changes on a healthy box: releases own compose files; config edits do not apply them. Documented, out of scope.

Rationale (recorded): credential rotation is over-engineering — a two-phase commit across DB roles, generated env, and five containers, with lockout and half-propagation failure modes, for an operation with zero historical demand. Rotation-by-edit would CREATE the broken-box risk it claims to prevent. Compromise recovery is a support operation; the restore path already re-imposes passwords.

Acceptance: slice-1 revert leaves cli tests green with the original gate restored; both generated files carry the headers verbatim on a fresh generate; no marker file is written or read; ticket closes as ruled-and-documented.
<!-- SECTION:DESCRIPTION:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Slice 1 (users.yml reapply) landed locally, foreman-reviewed and committed: checkUsersDone now compares .users.yml's sha256 against a marker (.users.yml.sha256, gitignored) written only after a successful users create upsert; changed file or missing marker → reconcile; absent file → no-op. Tests: marker gating (3 cases) + full cli/cmd suite green. Slices 2 (credential rotation re-ALTER) and 3 (healthy-box compose changes) remain — both need the King's ruling before build.

King (2026-09-01, retiring for the night): .users.yml is just to get started — he runs ./sb users create by hand after editing it, and that is fine. Slice 1's marker-gating is a convenience, not a correctness requirement; slices 2-3 are accordingly lower urgency and still await his ruling before any build.
<!-- SECTION:NOTES:END -->
