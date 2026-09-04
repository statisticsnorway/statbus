---
id: STATBUS-352
title: >-
  sensitivity by construction: the box-side Go closure is derived with `go list`, and a scenario is sensitive only to what it executes
status: To Do
assignee: []
created_date: '2026-09-04 10:20'
updated_date: '2026-09-04 10:20'
labels:
  - release
  - cli
  - cost
dependencies:
  - STATBUS-351
priority: high
type: task
ordinal: 345000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
## The problem

`ops/release/upgrade-sensitive-paths.txt` decides whether a scenario proven at an earlier candidate still covers a later one. It is a hand-written list of directory prefixes, and it is too coarse in two ways that cost VM hours on every candidate:

1. `cli/` is one entry, but `cli/` holds two different things. Box-side code runs on an installation: `./sb install`, the upgrade service, migrate, config, and their packages (`internal/upgrade`, `internal/migrate`, `internal/install`, `internal/config`, ...). Tool-side code runs only on a release engineer's laptop or a CI runner: `cmd/release*.go` and `internal/release` (the gates, `covered`, canary reads, drift checks). Nothing on a box ever runs `./sb release`, and the upgrade path does not import `internal/release`. Today a change to `cli/internal/release/coverage.go` rents 47 VMs to re-prove install and upgrade paths it cannot affect. Two such commits landed on 2026-09-04 alone.
2. `test/install-recovery/` is one entry, so every scenario is sensitive to every sibling scenario's script. rc.14's `covered` output, verbatim: `1-boot-concurrent-install must run` because `postswap-mid-tx-kill-arc.sh` changed. A scenario cannot be affected by a script it never runs.

Both are symptoms of one shape: the list names directories, and the truth is a set of files the box executes, which is a fact the code already knows.

## The one box-to-tool edge

`internal/migrate` imports five functions from `internal/release/immutability.go` (`MigrationInReleasedTag`, `MigrationExistsInTag`, `CurrentImmutabilityBaselineTag`, `FileIsDirty`, `IntentionallyFixBrokenImmutableMigrationEnvVar`). That file is self-contained (stdlib only, uses nothing else in the package). It belongs with migrate. Once it moves, `internal/release` is imported by nothing box-side, and the partition is real in the import graph.

## What to do

1. **Move `internal/release/immutability.go`** (and its test) to `internal/migrate/immutability.go`. Update `cmd/release.go` and `internal/release/predecessor.go` to import it from `migrate`. Assert with a test that `go list -deps` of the box-side commands does not contain `internal/release`.
2. **Split `cmd`:** `cli/cmd/release*.go` moves to `cli/cmd/release/` as its own package, registered from `main.go` (`release.Register(rootCmd)`). The only shared helper is `parseTwoLineStamp` (used by `types.go`), which moves to wherever `types.go` needs it. After this, `cli/cmd` is the box-side command set and `cli/cmd/release` is the tool-side set.
3. **Derive the Go part of the sensitivity set** in `cli/internal/release/sensitivity.go`: `BoxSidePackages(projDir, commit)` runs `go list -deps -f '{{.ImportPath}}' ./cmd` at the commit (via `git worktree` or `git archive` into a temp dir; `go list` needs the tree) and returns the module-relative directories. A changed `.go` file is sensitive if its directory is in that set, or if it is `go.mod`/`go.sum`. Delete `cli/` from the text list; the list keeps only non-Go artefacts.
4. **Per-scenario sensitivity for the harness:** a scenario is sensitive to its own script, `test/install-recovery/lib/`, `test/install-recovery/fixtures/`, `test/install-recovery/run.sh`, `dev.sh`, and its workflow file. Not to sibling scenario or arc scripts. `DecideCoverage` already receives the `Scenario`; give `DiffTouchesSensitivePath` the scenario so it can add these. Replace the blanket `test/install-recovery/` entry.
5. **The remaining text list** is exactly the non-Go artefacts the box executes or ships: `install.sh`, `migrations/`, `docker-compose`, `postgres/`, `caddy/`, `ops/statbus-upgrade.service`, `ops/setup-ubuntu-lts-24.sh`, `ops/notify-slack.sh`, `ops/release/`, `.github/workflows/images.yaml`, `.github/workflows/release.yaml`. `cli/cmd/sensitive_paths_list_test.go` keeps pinning each to a real path.
6. **Print the derivation**: `./sb release covered` already names the changed files that blocked coverage; add why each one is sensitive (`box-side package internal/upgrade`, `this scenario's script`, `listed artefact`).

## Done when

- A commit touching only `cli/cmd/release/` or `cli/internal/release/` reports every fleet scenario as covered by the prior candidate.
- A commit touching only `test/install-recovery/arcs/foo-arc.sh` reports every scenario except `foo` as covered.
- A commit touching `cli/internal/upgrade/service.go` reports every scenario as must-run, as today.
- A test asserts `internal/release` is absent from the box-side `go list -deps` closure.
- `ops/release/upgrade-sensitive-paths.txt` has no `cli/` and no `test/install-recovery/` entry, and its header says which part of the set is derived and from where.

## Why not runtime coverage instead

Runtime coverage (an instrumented `sb` writing a profile per scenario) would give the exact functions each scenario executed and is the more precise end state. It is STATBUS-353. This ticket is the structural prerequisite: it makes the box/tool split real in the tree, which coverage profiles then refine per scenario. Do this first.
<!-- SECTION:DESCRIPTION:END -->
