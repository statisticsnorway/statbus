---
id: STATBUS-352
title: >-
  sensitivity boundaries: choose a workflow-aware first slice, a same-binary policy closure, or a separate release binary
status: In Progress
assignee: []
created_date: '2026-09-04 10:20'
updated_date: '2026-09-04 20:58'
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
## Purpose

Reduce unnecessary paid install/recovery/upgrade reruns without ever inheriting
proof across a change that can affect the scenario or the meaning of its
evidence. The current directory-prefix list is too coarse, but the original
prescription is not safe or honest as written.

## Verified contradictions in the original design

### The proposed Go boundary is policy, not construction

Every current `sb` process initializes release command code:

- `cli/main.go` imports `cli/cmd` and calls `cmd.Execute()`.
- `cli/cmd/release.go`, `release_covered.go`, and `release_verify.go` register
  commands through package `init()` functions.
- `go list -deps ./cmd` therefore includes `cli/internal/release` today.

Moving release files to `cmd/release` and registering them from `main` does not
remove them from the shipped binary or Go's package initialization graph. A
future `go list -deps ./cmd` would be a deliberately selected box-command policy
subgraph, not the actual `sb` binary closure. Call it that or split the binary.

The actual migrate-to-release production edge is four function calls across two
files, not the five-symbol edge previously stated:

- `MigrationInReleasedTag` and `FileIsDirty` from `migrate.go`;
- `CurrentImmutabilityBaselineTag` and `MigrationExistsInTag` from
  `migrate_down_released_guard.go`.

The proposed command extraction is also not small: 17 release-prefixed files,
8 production plus 9 tests, total roughly 7,556 lines. Package-private root,
build-identity, exit-contract, Cobra, and test seams make the likely touched set
about 20 to 25 files.

### Historical `go list` is an optimizer with failure modes

`git archive` plus `go list -deps ./cmd` succeeded for HEAD and
`v2026.09.0-rc.14` in under one second with warm Go caches. With an empty module
cache and `GOPROXY=off`, it failed immediately because dependencies were
unavailable. Other old commits may need a different toolchain or unavailable
modules.

Therefore closure derivation must:

- fail open to `must run` with a visible diagnostic;
- never fail promotion closed merely because the optimizer cannot list an old
  tree;
- use the union of package directories at the evidence anchor and target, so a
  deleted or renamed former box package cannot disappear from the test;
- include `go.mod`, `go.sum`, build inputs, and future embed files;
- cache by commit rather than repeatedly archiving and listing the same tree.

### Scenario name alone is not the shell execution boundary

The install-recovery workflow runs `dev.sh`, which runs
`test/install-recovery/run.sh`. `run.sh` scans every scenario and arc script
before selecting one. Thus a sibling script is currently read by the controller
for every fleet scenario, even if the paid VM body never executes it.

The two smoke scenarios also have two different execution wrappers:

- smoke `0-happy-install` runs through `dev.sh test-install` and does not use
  `run.sh`;
- fleet `0-happy-install` runs through `dev.sh test-install-recovery`, `run.sh`,
  then the same scenario file;
- smoke `0-happy-upgrade` invokes its scenario directly;
- fleet `0-happy-upgrade` reaches it through `run.sh`.

Sensitivity therefore needs the full `Scenario`, including workflow identity,
not only the scenario name. If sibling scripts are to stop invalidating one
another, the single-selector `run.sh` path must first stop scanning sibling
contents, or the broader dependency must remain.

The original reduced text list was also incomplete. Arc execution reaches
`ops/ci-deploy-status.sh` and `ops/niue/sshdo*`; workflow and local-action files
interpret selection and admission; and coverage/sensitivity code changes the
meaning of inherited evidence. These are separate classes from box payload and
must be named honestly.

## Decision options

### Option 1: workflow-aware first slice, keep Go broad for now

Implement the hard evidence semantics first:

- make sensitivity depend on `Scenario` plus workflow identity;
- refactor or conservatively account for `run.sh` discovery;
- distinguish shared controller, workflow, own-script, library, fixture, and
  box-payload dependencies;
- replace substring matching with path-component/prefix matching;
- keep `cli/` sensitive, so no Go false-negative is introduced yet;
- preserve optimizer fail-open behavior and explain why every matched file is
  sensitive.

**Cost/risk:** low to medium refactor, safest first delivery. It saves sibling
scenario/arc reruns but does not yet save release-tool-only Go changes.

### Option 2: same-binary designated box-command policy closure

Do Option 1, then also extract release commands and migrate-owned immutability
primitives. Ban `init()` in the new release command package, register explicitly,
and derive anchor-union-target package directories for the designated box
command package. Add a compatibility/version rule so a changed coverage
interpreter cannot silently consume evidence under redefined semantics.

**Cost/risk:** medium to high refactor, high cost reduction. The release code is
still shipped and initialized by the one `sb` binary, so this is a documented
policy boundary, not an actual executable/import boundary.

### Option 3: separate box and release binaries

Move release commands to a separately built release-engineer/CI binary. The box
`sb` no longer imports or ships them, and `go list` can derive the actual box
binary closure.

**Cost/risk:** highest refactor and operations impact. This is the only simple
way to make the original “absent by construction” claim literally true, but it
changes command UX, build/release assets, workflows, and tool distribution.

## Recommendation and rulings needed

Recommend **Option 1 first**. It validates the difficult workflow/evidence
semantics with no Go false-negative and avoids moving 7.5k lines before the
boundary is honestly chosen. After measuring the saved fleet work, choose
Option 2 only if a documented same-binary policy boundary is acceptable; choose
Option 3 if actual absence from the box executable is required.

Before rewriting this into an implementation contract, rule:

1. Option 1, 2, or 3.
2. Default safety policy: a coverage-interpreter change forces fresh proof
   unless an explicit compatibility mechanism proves the change is monotonic.
3. Default shell policy: workflow discovery counts as a dependency until the
   global sibling scan is removed.
4. Default precision: keep `lib/` and `fixtures/` conservatively broad in this
   ticket; function/file-exact runtime precision remains STATBUS-353.

Read-only evidence and prototype output are in
`tmp/STATBUS-352-investigation.md` and `tmp/STATBUS-352-*`.
<!-- SECTION:DESCRIPTION:END -->
