---
id: STATBUS-349
title: >-
  fail-fast follow-ups from the string hunt: dead migrate exit 22, apply-latest's
  second tag classifier, isConnError by prose, and 15 smells
status: To Do
assignee: []
created_date: '2026-09-03 22:01'
updated_date: '2026-09-03 22:01'
labels:
  - upgrade
  - release
  - cli
  - correctness
dependencies:
  - STATBUS-348
priority: medium
type: enhancement
ordinal: 342000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Luna's repo-wide hunt (2026-09-03, tmp/luna-string-hunt.md, attached below verbatim) for the class the King retired on STATBUS-347/348: decisions carried in loose strings, nullable columns scanned into non-nullable Go types, exit codes shared between "refused to start" and "decided", discarded SQL results. Three DEFECTs are deferred here because they are pre-existing, not introduced tonight, and not release-gating; the 15 SMELLs are the backlog of "a type belongs here".

King's creed (rationale for every item): actionable fail-fast; make the invalid impossible to express; no loose string matching.

Deferred DEFECTs:
- D4: cli/internal/migrate/exit_codes.go declares ExitResource=22 for SQLSTATE class 53 but no producer emits it; a resource failure is labelled deterministic/20. Fix at the psql-owning boundary with a typed failure class.
- D5: cli/cmd/upgrade.go apply-latest has its own looser tag classifier (skips '-' on stable; accepts any v* on prerelease) beside the authoritative upgrade.ClassifyReleaseShape; a v2026.09.1-beta.1 could be applied on a prerelease box. Route through the shared classifier.
- D6: cli/internal/upgrade/service.go isConnError classifies context.Canceled / DeadlineExceeded and prose substrings as transport faults and retries them with an already-expired ctx. Distinguish context termination first; use errors.Is/As against pgx/pgconn/net sentinels.

Acceptance: each DEFECT fixed with a red-then-green test; each SMELL either fixed with the proposed type or explicitly ruled ACCEPTABLE-CONTRACT with the producer cited in code.
<!-- SECTION:DESCRIPTION:END -->

## Luna's report (DEFECT + SMELL sections, verbatim)

## DEFECT

### D1. Docker `unhealthy` is classified as healthy

- Consumer: `cli/cmd/install.go:961-964`
- Decision: `strings.Contains(string(out), "healthy")`
- Producer: `docker compose ps db --format "{{.Health}}"` at `cli/cmd/install.go:961`.
- Wrong today: Docker's health value `unhealthy` contains the substring `healthy`, so `checkServicesDone` returns true and the installer may skip the service-start/repair step for an unhealthy database container.
- Proposed type/contract: trim and compare the single formatted field exactly to `healthy`, or request Compose JSON and decode the health field into a typed status.

### D2. `release covered` exit 1 is both a decision and a refusal/error

- Verdict definition: `cli/cmd/release_covered.go:27-43`, `exitMustRun = 1`.
- Decision producer: `cli/cmd/release_covered.go:97-100` exits 1 when coverage was evaluated and found false.
- Refusal producer: `cobra.ExactArgs(2)` at `cli/cmd/release_covered.go:53` runs before `RunE`. Wrong argument count returns through `rootCmd.Execute()` and `cli/main.go:10-11` exits 1.
- The command's own documentation says bad arguments are exit 2 at `cli/cmd/release_covered.go:31`, but Cobra argument refusal is actually exit 1.
- Consequence: a workflow interpreting exit 1 as `must run` cannot distinguish a real coverage decision from a command that never evaluated coverage.
- Proposed contract: command-scoped error mapping at the outer boundary, with 0/1/2 reserved for covered/must-run/undecidable and a separate sysexits-style code for pre-dispatch/Cobra refusal.

### D3. root injection validation exits 2 before dispatch, colliding with `release covered`'s verdict space

- Refusal producer: `cli/cmd/root.go:393-400`, `inject.Validate()` failure followed by `os.Exit(2)`.
- Decision-space consumer: `cli/cmd/release_covered.go:43`, `exitUndecided = 2`.
- This runs before `rootCmd.Execute()`, so `sb release covered ...` with an invalid `STATBUS_INJECT_*` combination exits 2 without asking the coverage question. The caller sees the subcommand's `undecidable` code even though the command never started.
- Proposed contract: use `exitBinaryUnusable`/another non-verdict sysexits code for global pre-dispatch refusal.
- Stale comments from the earlier collision remain at `cli/cmd/root.go:56-60` and `cli/cmd/root.go:307`, both still saying the stale-binary guard exits 2 even though it now exits 69.

### D4. migrate resource exit 22 has no producer

- Declared contract: `cli/internal/migrate/exit_codes.go:8-43` says SQLSTATE class 53 maps to `ExitResource = 22`.
- Actual producer: `ClassifyUpErr` at `cli/internal/migrate/exit_codes.go:67-75` only maps psql exit 3 to `ExitDeterministic = 20`; every other error becomes 1.
- Process boundary: `cli/cmd/migrate.go:93-107` explicitly exits only 20 or the unrelated stale-restore 21. There is no production `os.Exit(migrate.ExitResource)`.
- Consumer: `cli/internal/upgrade/recovery_escalation.go:250-263` contains an exit-22 resource arm.
- Wrong today: a psql script failure caused by SQLSTATE 53 is still exit 3 and is therefore labelled deterministic/20. The separate resource branch is dead code and the documentation overstates the structured contract.
- Proposed contract: extract SQLSTATE in the psql-owning component and return a typed `UpFailureClass`, then map `insufficient_resources` to 22 at the command boundary. Do not classify the stderr in the upgrade parent.

### D5. `upgrade apply-latest` has a second, looser tag classifier

- Consumer: `cli/cmd/upgrade.go:433-458`.
- Decisions:
  - stable skips any tag containing `-` at `:443`;
  - prerelease accepts the first `v*` tag regardless of shape;
  - `ValidateVersion` then accepts arbitrary suffixes because `cli/internal/upgrade/github.go:48` allows `-[\w.]+`.
- Authoritative producer/classifier already exists: `upgrade.ClassifyReleaseShape` at `cli/internal/upgrade/github.go:58-132`, which explicitly rejects `-beta`, `-foo`, and typo suffixes as `ShapeUnknown`.
- Wrong today: on a prerelease box, a newest tag such as `v2026.09.1-beta.1` can be selected and applied even though the shared classifier says it belongs to no channel. A malformed newest `v*` can also make the command refuse instead of continuing to the newest valid tag.
- Proposed type: use `ReleaseShape`/`ReleaseTag` at the git-output boundary and filter by the configured channel through the existing classifier.

### D6. `isConnError` retries cancellation/deadline failures as stale connections

- Consumer/classifier: `cli/internal/upgrade/service.go:1245-1274`.
- Guessed strings: `conn closed`, `connection reset`, `context already done`, `context canceled`, `context deadline exceeded`.
- Producers: multiple unrelated layers, including Go context, pgx wrappers, net errors, and the caller's own cancellation. There is no single named producer or stable wire contract.
- Wrong today:
  - `errors.Is(err, context.Canceled)` and `context.DeadlineExceeded` are classified as connection faults even when the caller intentionally canceled or exhausted its operation budget.
  - The prose fallbacks can classify unrelated wrapped messages by wording.
  - `terminalConnDo` at `cli/internal/upgrade/service.go:9680-9721` retries with the same already-expired context and sleeps between attempts.
- Proposed type: distinguish `context` termination first and return it without retry. For transport failures, use `errors.Is`/`errors.As` against pgx/pgconn/net sentinels or a typed retryable connection error returned by the connection-owning helper.

## SMELL

### S1. Removed scenario helper names remain in a current-tense authority comment

See A1: `cli/cmd/release_coverage_authority.go:48-54` should name `release.ScenariosAt` and the `Scenario.Home` workflow.

### S2. `noSameKindTagAtHEAD` reimplements release shape with `v` and `-rc.` text tests

- Consumer: `cli/cmd/release.go:833-860`.
- Input producer: `git tag --points-at HEAD` at `:834` can return any repository tag.
- Decisions: `HasPrefix(tag, "v")` and `Contains(tag, "-rc.")`.
- A `v...-beta` or arbitrary `vfoo` tag is treated as a stable release tag. This is the exact footgun the authoritative `ReleaseShape` comment says not to duplicate.
- Proposed type: parse each tag through the shared release-tag smart constructor/classifier, ignore `ShapeUnknown`, and compare `ShapePrerelease` versus `ShapeRelease`.

### S3. PostgreSQL enums are cast and carried as plain strings in Go

Representative sites:

- `cli/internal/upgrade/service.go:1853-1871`: `release_status::text`, `docker_images_status::text`, and `release_builds_status::text` into `string` fields.
- `cli/internal/upgrade/service.go:1893`, `:1936`: string equality against `failed` and `commit`.
- `cli/internal/upgrade/service.go:2086-2092`, `:6366-6387`: Docker image status as `string`.
- `cli/internal/upgrade/service.go:4573`: `candidateMeta.releaseStatus string`.
- `cli/internal/upgrade/service.go:11095-11114`: `state::text` returned as `string`.

Producer: constrained PostgreSQL enum columns documented in `doc/db/table/public_upgrade.md:9,26,29-30`.

Proposed types: Go `UpgradeState`, `ReleaseStatus`, `DockerImagesStatus`, and `ReleaseBuildsStatus` types with exhaustive constants and validation at the pgx boundary. Avoid making downstream code depend on arbitrary strings after the DB has already supplied an enum contract.

### S4. retryability state is persisted inside human `error` prose

- Producer: `cli/internal/upgrade/service.go:6741-6744` writes `GIT_FETCH_FAILED_RETRYABLE: <prose>`.
- Consumer: `cli/internal/upgrade/service.go:8222-8246` uses `HasPrefix` to choose safe-to-reschedule guidance.
- Code-level assessment: this is currently a narrow named contract with one production producer.
- Schema-level smell: `public.upgrade.error` is documented nullable human text at `doc/db/table/public_upgrade.md:18`; retryability is machine state. A future rewording or manually supplied reason can alter operator guidance.
- Proposed type: nullable `failure_code` enum or `retryability` enum/boolean beside `error`, with `error` kept as prose only.

### S5. `commit_version` has a Go type, but DB carriers repeatedly erase it to `string`

- Canonical type: `cli/internal/upgrade/commit.go:37-41`, `type CommitVersion string`.
- Plain carriers include:
  - `cli/internal/install/state.go:80-85`, `ScheduledRow.Version string`;
  - `cli/internal/upgrade/service.go:1870`, `pendingRow.version *string`;
  - `cli/internal/upgrade/service.go:4571`, `candidateMeta.commitVersion string`;
  - `cli/internal/upgrade/service.go:6171-6173`, claim snapshot fields as strings.
- DB storage as nullable text is reasonable because the value is display-oriented and open-ended. The smell is losing the existing Go type at the read/write boundary.
- Proposed type: use `CommitVersion` and `*CommitVersion`/nullable wrapper in structs and smart-construct/fallback once when reading legacy NULLs.

### S6. nullable `scheduled_at` is scanned into plain `time.Time` without an SQL predicate

- Consumer: `cli/internal/upgrade/service.go:2086-2090`.
- Column: `public.upgrade.scheduled_at` is nullable, `doc/db/table/public_upgrade.md:15`.
- Query: `WHERE id = $1`, with no `state = 'scheduled'` predicate. Therefore the schema's scheduled-state constraint cannot prove non-null for this query.
- Current behavior: a NULL scan error is silently treated as `gerr != nil` and skips the image-claim gate before the guarded claim runs.
- Proposed type: `sql.NullTime`/`*time.Time`, or put `state='scheduled' AND scheduled_at IS NOT NULL` in the query and handle `ErrNoRows` explicitly.

### S7. `execObserved` decides statement kind by inspecting SQL source text

- Consumer: `cli/internal/upgrade/service.go:1009-1024`.
- String decision: upper/trim SQL and ask whether it starts with `UPDATE` before logging zero affected rows.
- Producers: many arbitrary SQL strings passed by callers, not one named producer.
- Failure mode: CTE-led updates (`WITH ... UPDATE`) and comments before an update are not recognised, so zero-row observations disappear depending on formatting.
- Proposed type: an explicit operation kind/expected-row policy parameter, or inspect the returned `pgconn.CommandTag` rather than the SQL source string.

### S8. structured container identity is flattened to prose and parsed back by prefix

- Producer: `evaluateContainersAtFlagTarget` at `cli/internal/upgrade/containers.go:79-114` emits strings beginning with `<service>: `.
- Consumer: `operatorServiceStateLines` at `cli/internal/upgrade/progress_contract.go:72-80` suppresses DB lines using `HasPrefix(mismatch, "db: ")`.
- A structured type already exists but is unused: `containerCheckResult` at `cli/internal/upgrade/containers.go:33-40`.
- Proposed type: return `[]containerCheckResult` and filter on `result.Service == "db"`; render prose only at the output edge.

### S9. install signer verification branches on Git's error prose

- Consumer: `cli/cmd/install.go:2324-2345`.
- String: `no signature found`.
- Producer: external `git verify-commit` stderr, not a repository-owned protocol.
- Decision: accept configured key existence if HEAD is unsigned; otherwise delete configured signer keys as invalid.
- A Git wording change sends an unsigned development commit down the wrong-key removal path.
- Proposed type/contract: establish signed/unsigned state with a separate structured Git object/signature probe or a documented exit/status command, then run key verification only for a confirmed signed commit.

### S10. PFX password classification has a prose fallback after a typed sentinel

- Consumer: `cli/cmd/cert.go:596-609`.
- String: lowercase error contains `decryption`.
- Producer: upstream `sslmate/go-pkcs12` error prose, alongside the already available `pkcs12.ErrDecryption` sentinel.
- The broad fallback can relabel non-password decryption failures as an invalid password.
- Proposed type: rely on `errors.Is(err, pkcs12.ErrDecryption)` and explicitly enumerate any proven alternate typed error from the library version in use.

### S11. arbitrary forward-step prose is labelled persistent by generic words

- Consumer: `cli/internal/upgrade/recovery_backoff.go:407-445`.
- Strings include `already exists`, `does not exist`, `violates`, `constraint`, `syntax error`, `undefined`, `cannot`, and `invalid input`.
- Producer: arbitrary nested command/error narratives, not one producer.
- Current control consequence: `cli/internal/upgrade/service.go:7134-7152` uses the result as a diagnostic label only, while observed state controls rollback direction. That limits harm, but the persisted label can still be false, for example a transient `cannot connect` message becomes `persistent-error`.
- Proposed type: pass a typed `StepFailureClass` from the step owner. Delete the prose classifier if it remains display-only and cannot be made authoritative.

### S12. refspec existence uses substring containment instead of line identity

- Consumer: `cli/cmd/install.go:1136-1142`.
- Producer: `git config --get-all remote.origin.fetch`, one refspec per output line.
- Decision: `strings.Contains(string(out), refspec)`.
- A larger/malformed refspec containing the canonical string can be accepted as exact configuration, especially on the fallback path after `NormalizeRefspecs` reports an error and install continues.
- Proposed contract: split lines, trim, and compare exact refspec values.

### S13. two production diagnostic `QueryRow` errors are discarded

- `cli/internal/upgrade/service.go:1753-1755`
- `cli/internal/upgrade/service.go:1798-1800`

Both are read-only probes after an artifact-status update error/zero-row result. The code logs `state` and `docker_images_status` even when the probe failed, yielding empty strings with no indication that observation failed.

Proposed handling: include the scan error in the diagnostic or emit an explicit `state=<unreadable>` result. These are not discarded writes, but they are `_ = QueryRow(...).Scan(...)` sites requested by the audit.

### S14. two live tests discard cleanup `ROLLBACK` results

- `cli/internal/upgrade/live_exec_observed_test.go:39`
- `cli/internal/upgrade/live_prune_test.go:43`

These are the only direct `_, _ = ...Exec(...)` results found across `cli/`. Both are test cleanup, not production writes. Closing the connection eventually rolls the transaction back, but a failed cleanup is hidden and can obscure the real state of a shared live-test connection.

Proposed handling: cleanup helper that records `t.Errorf`/`t.Logf` on rollback failure before connection close.

### S15. install image readiness is an untyped count of output lines

- Consumer: `cli/cmd/install.go:946-952`.
- Producer: `docker compose --profile all images -q`.
- Decision: at least four non-empty-ish lines means images are available.
- It does not prove which required services have images and can pass with four irrelevant/duplicate service image IDs while one required image is absent.
- Proposed type/contract: query the required service set and verify an image ID for each named service, preferably through Compose JSON/config output.


## Comments

<!-- COMMENTS:BEGIN -->
<!-- COMMENTS:END -->
