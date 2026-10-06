---
id: STATBUS-446
title: >-
  livedb test tier refuses to start when the developer checkout's .env.config
  still carries legacy secrets
status: In Progress
assignee: []
created_date: '2026-10-05 09:10'
labels:
  - testing
  - livedb
  - config
dependencies: []
references:
  - STATBUS-441
  - STATBUS-444
  - STATBUS-445
priority: medium
---

## Issue

Every livedb test fails in fixture setup, before any test runs:

    generate fixture config: exit status 1: Error: SLACK_TOKEN in .env.config is a secret; ...

`cli/internal/livedbtest/fixture.go` copies the developer checkout's `.env.config` and `.env.credentials` into the fixture project, then runs strict `./sb config generate`. A checkout whose `.env.config` predates the credential split still carries `SLACK_TOKEN` and `SEQ_API_KEY`. The coordinator's own checkout does, with 2 such keys (checked 2026-10-05). On such a checkout, strict generation refuses.

## Evidence

- STATBUS-441: `./dev.sh test-livedb` refused in a fresh worktree, and the targeted run had to use a hand-isolated project.
- STATBUS-444 re-review of d08cefdfd: the targeted `TestRollbackFinalizeHealthyTailCommitsAndUnlinks` could not start for the same reason, which left `restoreAndFinalize`'s snapshot-restore tail without livedb coverage.

## Principled fix

The fixture is an install of a project directory from operator files, so it should use the install-context generation every install path uses: `config generate --migrate-legacy-secrets`. That migrates the copied secrets into the fixture's own `.env.credentials`. The developer's real files are never touched, because the fixture works on copies.

## Acceptance criteria

- [ ] #1 The livedb fixture setup succeeds from a checkout whose `.env.config` carries legacy secrets. A unit test with a temp source checkout holding `SLACK_TOKEN` proves fixture config generation succeeds and leaves the source files byte-identical.
- [ ] #2 `TestRollbackFinalizeHealthyTailCommitsAndUnlinks` (or a sibling) runs in the direct livedb tier on this machine.

## Implementation steering (2026-10-06)

All six normal source gates at88327 are now green, with actual SQL/floor/livedb/Docker evidence read. At18:46:52 explicit bounded GO was delivered to `session_turkey_1791312412851_12cfd9d24181f570` (GPT6.1Sol low) under `tmp/446-fixture-authorization.md`. Exact base88327b58100e68d7d03db24963a0e190dc849576. Scope is the existing copied-project generation flag plus a regression exercising that call with synthetic source files and byte-identical source preservation. No application/schema/protocol change.

The author must observe baseline refusal and a succeeding minimal prototype before permanent edits, save explicit exits, freeze clean full40 and obtain independent MERGE before integration. For AC2, the existing actual target remains required. Before any DB creation or TestMain execution, the author must report the read-only verified endpoint/server version, exact new owned DB name, isolated project/pinned binary/private HOME. Only proposed `statbus_446_fixture_tail_1006` may be created/mutated after coordinator confirmation. No shared/prior-review DB drops/replays/bless/backend termination, operator secrets in the unit fixture, production/guest/install/callback, root source/index or user448/.yarn changes. Neither AC is credited yet. Earlier20-line Tiger report `tmp/446-fixture-preparation.md` was preparation only.

### Frozen source and runtime approval, 2026-10-06 19:01 UTC

Author froze82f36bd0f2b90e6466c15ce212fc9f7eb98165f8: actual shared copied-project generation invokes the existing --migrate-legacy-secrets flag, plus a real CLI synthetic regression proving migrated destination and both source files byte-identical. Baseline refused with exit1, prototype/final exited0. Full tagged lint exposed two pre-existing unchecked deferred Close results in cmd live452 tests; a separately authorized two-annotation child97f24e552ec0890c967f8e0b3341c1cc63ff6d54 fixes only those results. Final four-path delta+86/-3, clean full40, focused fixture0, build/vet/taggedvet/compile-c/format/diff0 and full regular/tagged lint0 issues read. Original lint1 retained. No broad suite or tagged TestMain from compile-c.

Actual read-only psqlTCP and pgxTCP verify127.0.0.1:3014 postgres PG18.6 and absence of ONLY new statbus_446_fixture_tail_1006. Seed floor20261001163000 is explicitly older than current source floor; no shared seed migration/bless/replay authorized. Existing missing-role-credential error returns before Docker or ALTER ROLE. At19:01:11 coordinator authorized ONLY that new clone and the existing target with owned project/final pinned sb/private HOME/dual overrides/minimal0600 .env/empty callback. Runtime result remains pending. The target proves real SQL/held marker/read-only/flock/audit boundaries, with mocked Docker/start and empty backup path, not actual snapshot restore or guest recovery.

Fresh Whale Solxhigh independent review of exact97f24 delegated19:01:20, full tmp/446-fixture-review.md verdict pending. No source integration, push or AC completion from green notifications. Implementation report tmp/446-fixture-implementation.md and raw logs in author's tmp/446/ retain exact old/final evidence.
