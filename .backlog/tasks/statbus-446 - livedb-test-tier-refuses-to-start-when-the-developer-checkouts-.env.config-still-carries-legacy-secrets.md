---
id: STATBUS-446
title: >-
  livedb test tier refuses to start when the developer checkout's .env.config
  still carries legacy secrets
status: To Do
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
