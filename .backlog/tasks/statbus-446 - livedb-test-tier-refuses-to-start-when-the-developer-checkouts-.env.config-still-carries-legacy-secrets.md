---
id: STATBUS-446
title: >-
  livedb test tier refuses to start when the developer checkout's .env.config
  still carries legacy secrets
status: Done
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

- [x] #1 The livedb fixture setup succeeds from a checkout whose `.env.config` carries legacy secrets. A unit test with a temp source checkout holding `SLACK_TOKEN` proves fixture config generation succeeds and leaves the source files byte-identical.
- [x] #2 `TestRollbackFinalizeHealthyTailCommitsAndUnlinks` (or a sibling) runs in the direct livedb tier on this machine.

## Implementation steering (2026-10-06)

All six normal source gates at88327 are now green, with actual SQL/floor/livedb/Docker evidence read. At18:46:52 explicit bounded GO was delivered to `session_turkey_1791312412851_12cfd9d24181f570` (GPT6.1Sol low) under `tmp/446-fixture-authorization.md`. Exact base88327b58100e68d7d03db24963a0e190dc849576. Scope is the existing copied-project generation flag plus a regression exercising that call with synthetic source files and byte-identical source preservation. No application/schema/protocol change.

The author must observe baseline refusal and a succeeding minimal prototype before permanent edits, save explicit exits, freeze clean full40 and obtain independent MERGE before integration. For AC2, the existing actual target remains required. Before any DB creation or TestMain execution, the author must report the read-only verified endpoint/server version, exact new owned DB name, isolated project/pinned binary/private HOME. Only proposed `statbus_446_fixture_tail_1006` may be created/mutated after coordinator confirmation. No shared/prior-review DB drops/replays/bless/backend termination, operator secrets in the unit fixture, production/guest/install/callback, root source/index or user448/.yarn changes. Neither AC is credited yet. Earlier20-line Tiger report `tmp/446-fixture-preparation.md` was preparation only.

### Frozen source and runtime approval, 2026-10-06 19:01 UTC

Author froze82f36bd0f2b90e6466c15ce212fc9f7eb98165f8: actual shared copied-project generation invokes the existing --migrate-legacy-secrets flag, plus a real CLI synthetic regression proving migrated destination and both source files byte-identical. Baseline refused with exit1, prototype/final exited0. Full tagged lint exposed two pre-existing unchecked deferred Close results in cmd live452 tests; a separately authorized two-annotation child97f24e552ec0890c967f8e0b3341c1cc63ff6d54 fixes only those results. Final four-path delta+86/-3, clean full40, focused fixture0, build/vet/taggedvet/compile-c/format/diff0 and full regular/tagged lint0 issues read. Original lint1 retained. No broad suite or tagged TestMain from compile-c.

Actual read-only psqlTCP and pgxTCP verify127.0.0.1:3014 postgres PG18.6 and absence of ONLY new statbus_446_fixture_tail_1006. Seed floor20261001163000 is explicitly older than current source floor; no shared seed migration/bless/replay authorized. Existing missing-role-credential error returns before Docker or ALTER ROLE. At19:01:11 coordinator authorized ONLY that new clone and the existing target with owned project/final pinned sb/private HOME/dual overrides/minimal0600 .env/empty callback. Runtime result remains pending. The target proves real SQL/held marker/read-only/flock/audit boundaries, with mocked Docker/start and empty backup path, not actual snapshot restore or guest recovery.

Fresh Whale Solxhigh independent review of exact97f24 delegated19:01:20, full tmp/446-fixture-review.md verdict pending. No source integration, push or AC completion from green notifications. Implementation report tmp/446-fixture-implementation.md and raw logs in author's tmp/446/ retain exact old/final evidence.

At19:03 coordinator read the full51-line updated report and raw target/preflight/postflight/filesystem logs. Existing TestRollbackFinalizeHealthyTailCommitsAndUnlinks executed once at97f24, PASS0. Only new statbus_446_fixture_tail_1006 cloned, floor remains20261001163000. Actual held marker, ALTER DATABASE read-only teardown, terminal rolled_back stamp/pending cleared, maintenance removal and flock release passed; cleanup leaves no probe row or target audit/log/bundle/marker. All five runtime exits0, source still clean97f24. Ordered audit assertion passed, but its printed list also contains retained inherited seed history for reused id1, so this is not claimed as isolated exactly-two-event provenance. Mocked Docker/start and no snapshot/binary restore remain explicit limits. Owned DB retained, no shared or role mutations. Independent review still pending before integration/Done.

At19:06:32 the full175-line Whale independent review was read: explicit MERGE exact97f24, both bounded ticket criteria demonstrated, no concrete source blocker. Source integrated19:07:04 as bfab97dfc014f851ef765c3ebcb5a650014f718f and e697355ccb66dcf05ed29f101701b3530e160d00. Both stable patch IDs and complete non-backlog source equality verified in tmp/446-reviewed-source-proof-20261006.log. Coordinator sole full ordinary Go suite659142lmqr runs at exact integrated source, explicit log/exit pending. No tagged TestMain repeat or push. Ticket closure and normal source CI are separate milestones; future guest/deployed gates remain unchanged.

### Completion, 2026-10-06 19:10 UTC

The sole full ordinary `go test ./... -count=1` passed at exact integrated e697355ccb66dcf05ed29f101701b3530e160d00, process exit0,150.93s. Logs tmp/446-full-go-e697355cc.{log,exit}; cmd51.879s, upgrade142.113s, copied-generation package5.410s. Final build/vet/full regular and tagged lint were already green at reviewed source, and independent checks passed. AC1 is demonstrated at the actual shared copied-generation boundary with synthetic real CLI and byte-identical originals. AC2 is the existing actual direct-livedb target PASS0 with all explicit runtime limits above. Both criteria and reviewed integration are complete, so status Done. This does not mark future named-candidate, snapshot restoration or deployment gates complete. Fresh all-CI-idle check, source push and hosted gate evidence remain separate release tasks.

### Hosted source evidence, 2026-10-06 19:37 UTC

The single source push at19:13:49 followed a fresh all-pages/all-active-status CI-idle check. All six expected workflows succeeded at exact `619ffc194801bf6eeb0e3f81608db512afaaffd5`: app37517380592, Notify37517380599, Go37517380778, Harness37517380783, Images37517380883 and attributed Fast37517922535. Sole observer0538054gwi completed exit0 at19:33:24. No rerun or second push.

Final Fast JSON and full2966-line log are retained in `tmp/446-fast-619ffc194-final.{json,log}`. Full delegated23-line extraction and coordinator raw evidence reads establish102 shared plus1 isolated SQL tests passed, an actual empty-database402-migration replay through20261006132000, all11 verbose daemon-floor probes passed, and livedb upgrade190.373s/install3.701s package success. Real Docker seed extraction and compose-model/profiled-container probes passed; containers/networks/volumes were removed. Failure diagnostics were skipped because SQL passed. The SQL suite used the published matching seed; the separate floor replay was from empty. The local-source CLI was built by CI, not downloaded as a published binary.

Full Harness evidence was separately read from its946-line log. This closes hosted source evidence only. Nonverbose livedb package output does not individually print the rollback-tail test, whose direct local PASS is recorded above. No named-candidate guest install/recovery, actual snapshot restore, fleet/deployment, security clearance or Norway canary is claimed. Reports `tmp/446-fast-evidence-619ffc194.md` and `tmp/446-harness-evidence-619ffc194.md` retain these boundaries.
