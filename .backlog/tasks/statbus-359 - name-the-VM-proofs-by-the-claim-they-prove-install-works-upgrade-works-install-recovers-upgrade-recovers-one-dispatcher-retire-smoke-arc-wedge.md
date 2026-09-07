---
id: STATBUS-359
title: >-
  Name the VM proofs by the claim they prove: install-works, upgrade-works, install-recovers, upgrade-recovers; one dispatcher; retire smoke, arc, wedge
status: To Do
assignee: []
created_date: '2026-09-07 07:56'
updated_date: '2026-09-07 13:07'
labels:
  - harness
  - release
  - naming
dependencies: []
---

## Ruling (owner, 2026-09-07)

The paid VM proofs get four names that state the North Star in the name,
what the test helps us ensure is the case:

| subject \ claim | nothing breaks | something breaks at one exact point |
|---|---|---|
| install | `install-works` | `install-recovers` |
| upgrade | `upgrade-works` | `upgrade-recovers` |

Each name reads as the sentence the test proves. A red run reads as its
negation, which is exactly the news an operator needs.

**All other tribal language goes:** `smoke`, `arc`, `arcs`, `-arc.sh`,
`wedge`, `fleet` (as a test-family name), `harness` (as a family
qualifier). `scenario` stays only as the generic word for "one test file";
it is not a family name. Where the tribal word carried a real distinction
(STATBUS-071's "arc" meant real register+schedule dispatch, never
fabricated state) that distinction is now universal doctrine, enforced by
`run.sh`'s forbidden-shape scan, so the word distinguishes nothing.

Why not the conventional pairs: "sad path" means "bad input rejected
gracefully" in test vocabulary, but our recovery tests inject a kill or an
error into a VALID run and demand recovery, so "sad install" misleads.
"Sunny/rainy", "nominal/off-nominal" are symmetric but say nothing about
recovery. The verb pair names the proof, not the input.

## Ground truth today (three families, three dispatch paths)

| today | files | dispatched by | judged by |
|---|---|---|---|
| "smoke" | `scenarios/0-happy-install.sh`, `scenarios/0-happy-upgrade.sh` | `test-smoke.yaml`'s own `case` | `checkSmokeGate` |
| "install-recovery scenarios" | `scenarios/*.sh` (15 incl. the two above) | `run.sh --print-selected` → `install-recovery-harness.yaml` | `checkInstallRecoveryHarnessGate` |
| "upgrade arcs" | `arcs/*-arc.sh` (33) | `upgrade-arc-harness.yaml` builds lineage branches itself, calls `arcs/<name>-arc.sh` | `checkUpgradeArcHarnessGate` |

All three already share `lib/` (vm-bootstrap, assertions, data-helpers,
wedge-helpers, release-baseline, arc-helpers) and one VM shape. The
difference is only in who selects and who constructs the lineage.

One straggler: `scenarios/3-postswap-worker-ddl-deadlock.sh` registers and
schedules a real upgrade, so it is an `upgrade-recovers` test living in the
install family.

Word census at the time of ruling (tracked files, excluding backlog,
archive, tmp): `arc` 118 files, `wedge` 85, `arcs` 53, `smoke` 39. Heaviest:
`test/install-recovery/arcs` (33), `cli/internal/upgrade` (23),
`cli/internal/release` (13), `cli/cmd/release` (10), `.github/workflows` (8),
`lib/` (8), `doc` + `doc/diagrams` (13).

## Target shape

```
test/vm/                              (or keep test/install-recovery/ renamed; rule below)
  run.sh                              ONE dispatcher for all four cells
  lib/                                shared, unchanged in substance
  install-works/     <name>.sh        1
  upgrade-works/     <name>.sh        1 + today's `working` lineage fixture
  install-recovers/  <name>.sh        13 (today's 1-boot-*, 5-install-*)
  upgrade-recovers/  <name>.sh        32 (today's arcs minus `working`, plus 3-postswap-worker-ddl-deadlock)
```

- The cell is the directory; the file name drops every prefix and suffix
  (`0-`, `1-boot-`, `5-install-`, `-arc`). Phase ordering that the prefixes
  carried moves to a `# phase:` header line `run.sh` can sort on, or is
  dropped if nothing consumes it (verify before deciding).
- `run.sh` selects by cell, by name, or all; `--list` and
  `--print-selected` keep their contract. Lineage construction that
  `upgrade-arc-harness.yaml` does today moves into a `lib/` helper the
  upgrade tests call, so the workflow is a thin matrix over `run.sh` output
  like the fleet workflow already is.
- Workflows: `test-smoke.yaml` → `install-works` + `upgrade-works` run
  first because they are cheap (the ladder's rungs 4 and 5 keep their
  place; only the label changes). `install-recovery-harness.yaml` →
  `install-recovers.yaml`; `upgrade-arc-harness.yaml` →
  `upgrade-recovers.yaml`. Job ids in `release-fleet-orchestrator.yaml`
  follow.
- `coverage.go` `Scenario.Home` takes the cell name; the ownership rule in
  `doc/release-ladder.md` ("Fleet owns exactly `scenarios/<name>.sh`; arcs
  own exactly `arcs/<name>-arc.sh`") becomes "each cell owns exactly
  `<cell>/<name>.sh`".
- Gate readers `checkSmokeGate`, `checkInstallRecoveryHarnessGate`,
  `checkUpgradeArcHarnessGate` → one reader per cell with the cell name.
- `lib/arc-helpers.sh` and `lib/wedge-helpers.sh` get names that say what
  they contain (dispatch helpers, fault-injection helpers); `inject` stays
  since it is the mechanism, not a family.
- `doc/release-ladder.md`, `README.md`, `doc/CLOUD.md`, AGENTS.md,
  `dev.sh` help text, `.claude/hooks/*`: all four names, no old words.
- Backlog and `doc/archive` are history and are NOT rewritten.

## Also in scope: the pg_regress CI job names (owner, 2026-09-07)

Ground truth: `fast-tests.yaml` (GitHub runner) and `pg_regress.yaml`
(niue, self-hosted) both run `./dev.sh migrate-and-test fast`, the same 98
tests. The runner job is THE per-commit oracle; the niue job is the fallback
for when we choose to run it ourselves, not a second gate. The names must
say that ("pg_regress" vs "pg_regress fallback (self-hosted)" or similar),
and nothing should wait on the fallback. The 4xx/5xx tier is deliberately
outside CI (too slow); tests that are not slow must not live there (the
349 and 347 repair tests were renumbered out of it).

## Rulings still open (write the answer here before the work starts)

1. Directory: `test/vm/` (says what they are: paid VM proofs) or keep
   `test/install-recovery/` as the umbrella with the four cells inside?
   The umbrella name is itself a family word, so `test/vm/` is the
   consistent choice; ruling wanted because it moves 50 files' paths.
2. `dev.sh` verbs: `test-install` today runs a Multipass happy install;
   `test-install-recovery` runs the paid fleet. Proposed: `./dev.sh
   test-vm <cell|name|all>` as the one entry, with `test-install` kept as
   the free local Multipass check under a name that says so
   (`test-install-local`).

## Sequencing (owner rule: never during a paid run)

Mechanical, wide, and it invalidates every coverage proof by design (the
paths move, so `DecideCoverage` sees every home changed). So:

1. Land AFTER the current queue (STATBUS-035/339 paid run, 337, 341, 354)
   and after the batch RC is cut, or immediately before a fresh RC whose
   full ladder will run anyway. Never between an RC tag and its proofs.
2. One implementer, one commit series: (a) `git mv` with zero content
   change so history follows; (b) `run.sh` + lineage helper; (c)
   workflows + orchestrator job ids; (d) Go: homes, gate readers, tests;
   (e) docs and hooks; (f) word sweep with the census re-run to zero.
3. Prove without paying: `run.sh --list` and `--print-selected` per cell
   match today's counts (2 / 13 / 1+1 / 32) before and after; `go test
   ./cli/...` green (`workflow_triggers_test`,
   `workflow_fleet_concurrency_test`, `architecture_test`,
   `release_arc_domain_gate_test` all pin workflow and path names and must
   be updated, not deleted); `bash -n` and shellcheck on every moved file;
   `actionlint` on the workflows; `./sb release covered` against the last
   RC reports every cell as uncovered (expected, by design) and against the
   next RC's tag reports covered once its ladder is green.
4. The next RC after landing runs the full ladder; that run is the
   acceptance.

## Acceptance

1. The four names are the only family names in tracked, non-archive files;
   `git grep -wiE 'smoke|arcs?|wedge' -- ':!.backlog' ':!doc/archive'`
   returns only hits that are not test-family usage (each remaining hit
   listed in the evidence with its reason, e.g. `arc` in an unrelated
   identifier).
2. One `run.sh` dispatches all four cells; the three workflows are thin
   matrices over its output.
3. Counts preserved and named per cell in `--list`.
4. Coverage, gates, ladder doc, and orchestrator use the cell names.
5. The first full ladder on the next RC is green with the new names.
