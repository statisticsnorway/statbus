---
id: STATBUS-352
title: >-
  sensitivity boundaries: workflow-aware scenarios and a bounded same-binary Go policy closure
status: In Progress
assignee: []
created_date: '2026-09-04 10:20'
updated_date: '2026-09-05 09:13'
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

Reduce unnecessary paid install, recovery, and upgrade reruns without ever
inheriting proof across a change that can affect:

1. the code exercised on the installation;
2. the selected scenario or its controller;
3. the meaning, discovery, or interpretation of the evidence.

The optimizer may fail open by running more tests. It must never manufacture a
false covered verdict. Promotion authority remains fail-closed on missing proof.

## Decided structural direction

Keep one operator-facing `sb` executable. Do not create a separate release
binary and do not reorganize the whole CLI.

The current active Go structure is semantically sound:

```text
cli/
  main.go                 process entrypoint and composition
  cmd/                    Cobra command-line adapter
  internal/<capability>/  install, migrate, upgrade, release, config, and other implementation packages
```

- `cli/` is the appropriate component name in this polyglot repository because
  it is the Go module that builds `sb`.
- `cmd` and `internal` are different axes, not competing layouts. `cmd` defines
  how an operator invokes a capability. `internal/<capability>` implements it
  and is protected by Go's internal-package import rule.
- Do not introduce a `box/` source hierarchy. “Box-side” is a proof policy and
  execution context, not a stable product capability.
- Tracked legacy Crystal files under `cli/src`, `cli/spec`, and `cli/shard.*`
  are the separately tracked STATBUS-093 cleanup and are explicitly outside
  this ticket.

The delivery is staged. First make the shell execution boundary truthful while
keeping all `cli/` changes conservatively sensitive. Then prototype, and only if
bounded, extract the release command surface into a compiler-enforced package
boundary inside the same binary.

## Why a Go directory move is a package extraction

In Go, one directory is one package. Files cannot move from `cli/cmd` to
`cli/cmd/release` while remaining part of package `cmd`. The moved files must
become a separate package, proposed path `cli/cmd/release` with package name
`releasecmd`.

That is not a new runtime framework, plugin, service, executable, or deployment
artifact. It is a compile-time source boundary. It nevertheless needs explicit
wiring because the current release files use private package state and three
`init()` functions register commands on the shared `rootCmd`.

A file-prefix-only rule such as `cli/cmd/release*.go` would be cheaper but is not
an enforceable dependency boundary. The files could still mutate shared package
state or call private ordinary-command code, and `go list` cannot derive
file-level dependency closures. Therefore the choices are:

- keep `cli/` broad; or
- create a real package boundary and enforce its import direction.

Do not claim release code is absent from the executable. It remains compiled and
shipped in `sb`. The honest contract is a **designated same-binary policy
closure**: ordinary command code cannot depend on the release command or release
engine packages, while `main.go` explicitly composes both command surfaces.

## Current `run.sh` dependency problem

The install-recovery workflow executes:

```text
install-recovery-harness.yaml
  -> ./dev.sh test-install-recovery
    -> test/install-recovery/run.sh
      -> one selected scenario script
        -> one Hetzner VM
```

The free `discover` job calls `run.sh --print-selected` to construct the matrix.
Each paid matrix job later calls the same runner with one exact scenario slug.

Today `run.sh` scans every `scenarios/*.sh` and `arcs/*.sh` for forbidden
fabrication and direct `public.upgrade` ledger writes before it parses any flag
or selector. It then discovers every scenario and reads candidate files for the
`HARNESS_SKIP_DEFAULT` marker. Consequently an exact invocation for scenario A
really reads sibling B. A change to B can make A's invocation fail, so current
A evidence cannot honestly be inherited across B.

The global structural guard is valuable and must remain fail-fast. The defect is
that every paid exact-scenario job repeats global domain validation.

## Work package A: truthful shell and workflow boundary

### A1. Prototype before permanence

Create a non-destructive prototype under `tmp/` that directly observes which
scenario files an exact invocation reads. The prototype must prove both:

1. global validation still detects a forbidden construct in any sibling before
   the workflow can start a paid matrix job;
2. after successful discovery, exact execution of scenario A no longer reads
   sibling scenario contents.

Use real runner interfaces or a faithful temporary harness tree. A source-code
inspection alone is not sufficient evidence.

### A2. Separate domain validation from exact paid execution

Refactor the existing runner rather than adding a second selection algorithm:

- domain discovery/validation scans every scenario and arc, applies known-red
  rules, resolves selectors, and emits the matrix;
- the release-fleet orchestrator must run target-commit domain validation before
  it may accept an all-covered result, including when no paid harness is
  dispatched; a structural violation is a visible red diagnostic, never a
  covered verdict;
- the existing free `discover` jobs in the install-recovery and upgrade-arc
  harnesses perform the same authoritative validation before any matrix job
  becomes eligible;
- exact matrix execution accepts one already-discovered slug, validates that it
  is a safe basename and existing scenario, and executes only that file;
- exact execution must not inspect sibling scenario contents;
- local full runs and broad selectors retain global validation;
- do not weaken the no-fabrication or no-ledger-write doctrine;
- do not duplicate selector, known-red, or structural-validation algorithms.

A dedicated exact mode is preferable to guessing from positional arguments if
that makes the trust boundary explicit. The workflow must only enter exact mode
with matrix values emitted by the successful discovery job.

### A3. Make sensitivity scenario and workflow aware

Sensitivity must consume the full `release.Scenario`, including `Name` and
`Home`, rather than a bare slug. Smoke and fleet scenarios with the same slug
have different wrappers and dependencies.

Classify changed paths by reason:

- **box payload**: code or configuration executed by the installation;
- **shared controller**: runner, workflow, local action, and orchestration files
  that affect every scenario in their domain;
- **own scenario**: the selected scenario or arc script;
- **shared harness input**: common libraries and fixtures;
- **proof interpreter**: coverage, scenario identity, evidence, and sensitivity
  semantics.

Required first-slice policy:

- a selected scenario or arc is sensitive to its own script, not sibling script
  contents after A2 makes that true;
- shared runners, workflows, actions, and controllers invalidate the scenarios
  they control;
- `test/install-recovery/lib/` and fixtures remain conservatively broad in this
  ticket;
- upgrade arcs include the operations helpers they actually call, including
  `ops/ci-deploy-status.sh` and `ops/niue/sshdo*`;
- path matching uses repository-relative path components or prefixes, never
  accidental substring containment;
- every must-run verdict explains the matched path and sensitivity reason;
- changes to the sensitivity/evidence interpreter force fresh proof unless a
  future explicit compatibility mechanism proves the change monotonic;
- the real `./sb release covered` and `covered-subset` interfaces remain the
  single decision authority used by CI and promotion.

During Work package A, retain the current broad `cli/` classification. No Go
false-negative is permitted while the package boundary is undecided.

## Work package B: bounded `cmd/release` extraction prototype

Prototype the package move in a disposable scratch change after A is independently
reviewed. The prototype must report:

- exact production files and tests moved;
- every private `cmd` symbol needed by release commands;
- every non-release production file that requires a semantic change;
- the proposed acyclic import graph;
- the explicit registration seam in `main.go`;
- whether all Go tests compile and pass;
- whether command names, flags, exit codes, build identity, stale-binary guard,
  and verbosity behavior remain unchanged.

### Bounded go/no-go gate

Proceed to permanent extraction only if all of these are true:

1. The repository still builds one binary named `sb` with unchanged operator UX.
2. Ordinary command registration is not rewritten. Existing non-release
   `init()` registration can remain outside the new package.
3. No dependency-injection framework, plugin mechanism, command registry
   framework, or second executable is introduced.
4. The intended graph is enforceable and acyclic:

   ```text
   main -> cmd
   main -> cmd/release
   cmd/release -> internal/release and shared internal capabilities
   cmd -X-> cmd/release
   cmd -X-> internal/release
   ```

5. Release command registration is explicit and the new package contains no
   `init()` function or side-effectful package-global registration.
6. Package-private needs fit a small, named command context or a few narrowly
   exported read-only accessors. They do not require exposing general `cmd`
   internals.
7. No more than eight existing non-release production Go files require semantic
   modification. File moves, moved tests, generated formatting, and new focused
   architecture tests do not count against this limit.
8. Focused and full `go test ./...` pass in the prototype.

If any condition fails, stop the Go narrowing. Record the observed blocker,
retain `cli/` as broadly sensitive, and complete the safe shell improvement
without forcing a larger CLI redesign. That is an authorized conservative
outcome, not permission to weaken the boundary with a filename convention.

## Work package C: same-binary Go policy closure, only after B passes

### C1. Package ownership

- Move the release-prefixed command production files and their tests to
  `cli/cmd/release` as package `releasecmd`.
- Replace the three release `init()` functions with explicit construction and
  registration from `main.go`.
- Preserve all command names, flags, help, exit contracts, build identity,
  staleness behavior, and tests.
- Do not refactor unrelated command registration.

### C2. Correct dependency ownership

`internal/migrate` currently imports `internal/release` for four production
functions:

- `MigrationInReleasedTag`;
- `FileIsDirty`;
- `CurrentImmutabilityBaselineTag`;
- `MigrationExistsInTag`.

Move these migration immutability primitives to migration-owned code. Release
machinery may depend on migration capabilities, but migration execution must not
depend on the release engine merely to make the policy closure appear smaller.

Add architecture tests that fail if:

- ordinary `cmd` imports `cmd/release` or `internal/release`;
- migration code imports the release engine again;
- the new release command package gains an `init()` function;
- command composition stops being explicit at the process entrypoint.

### C3. Historical closure derivation

The designated box-command policy closure is the dependency set of ordinary
`./cmd`, not the complete `sb` executable closure. Name and document it honestly.

For a coverage decision from evidence anchor A to target T:

- derive package directories at both A and T;
- use their union, so a deleted or renamed former dependency cannot disappear
  from sensitivity;
- include `cli/main.go`, `go.mod`, `go.sum`, build inputs, and future embedded
  files explicitly;
- cache derived closures by commit;
- use historical source trees without mutating the working tree;
- preserve current broad sensitivity when the package boundary was not present
  at an older commit.

Historical `go list` is an optimizer. Old toolchains, unavailable modules, an
empty module cache, archive errors, or parse errors may make it undecidable. Any
such failure must:

1. return **must run** for the affected scenarios;
2. emit a visible, actionable diagnostic through `coverage-question-health`;
3. never return covered;
4. never turn optimizer unavailability into a promotion-infrastructure success.

The promotion gate still requires actual current or safely inherited evidence.

### C4. Proof interpreter policy

Do not split `cli/internal/release` into finer subpackages in this ticket unless
the B prototype demonstrates that doing so is required for an acyclic extraction
and remains inside the same stop gate.

Initially treat every change under `cli/internal/release/` conservatively as
proof-sensitive. That package contains release evidence, scenario,
workflow-check, coverage, predecessor, canary, and sensitivity behavior whose
interactions determine whether proof may be inherited. A release command UI
change confined to the extracted `cli/cmd/release/` package may be outside box
payload, but it must still pass the ordinary Go and release-machine tests
appropriate to that code. No previous paid evidence may be consumed under
silently redefined semantics.

## Validation contract

### Shell and workflow

- `bash -n` for every changed shell script;
- `actionlint` and YAML parsing for changed workflows/actions;
- focused regression tests for global guard, known-red selection, exact slug
  validation, duplicate selection, full selection, and sibling independence;
- direct observation that exact execution does not read sibling contents;
- real-command coverage tests through `./sb release covered` and
  `./sb release covered-subset` for own, sibling, shared, smoke, arc, and
  undecidable cases.

### Go boundary, if B passes

- focused package and architecture tests;
- `cd cli && go test ./... -count=1`;
- unchanged `./sb --help`, release command help, flags, and exit contracts;
- historical closure tests at HEAD, the latest release candidate, a commit
  before package extraction, a deleted dependency, and an unavailable-module
  fixture;
- fail-open full-suite decisions plus a red diagnostic on undecidable closure;
- `git diff --check`.

### Review and live proof

- independent adversarial review after Work package A;
- a fresh independent adversarial review after Work package C, if it proceeds;
- no paid Hetzner run and no RC solely for this ticket;
- the later batch RC must exercise the live optimized orchestrator and prove
  that scenarios selected as covered or must-run match the checked-in policy.

## Acceptance criteria

1. The repository retains one `sb` binary and the established `cli`, `cmd`, and
   `internal` structure.
2. Global install-recovery validation still blocks the orchestrator's coverage
   decision and the harness workflow before any paid scenario can start, even
   when the computed paid subset is empty.
3. Exact paid execution no longer reads sibling scenario contents.
4. Sensitivity is keyed by full scenario/workflow identity and explains every
   invalidating path by reason.
5. Libraries and fixtures remain safely conservative, and all known arc/helper
   and workflow/action edges are represented.
6. `cli/` remains broad unless the bounded Go prototype passes every go/no-go
   condition.
7. If extraction proceeds, compiler-enforced import direction and historical
   anchor-union-target closure replace the broad `cli/` rule without claiming
   release code is absent from the binary.
8. Every derivation failure runs more proof and produces a visible diagnostic.
9. All focused and full local validation passes, and both implementation slices
   receive independent review.
10. Ticket evidence records which Go outcome occurred: bounded extraction landed,
    or broad Go sensitivity was deliberately retained after an observed stop.

## Non-goals

- a second release binary;
- renaming `cli`, `cmd`, or `internal`;
- reorganizing every Cobra command;
- removing all existing non-release `init()` registration;
- cleaning legacy Crystal sources, which remains STATBUS-093;
- exact function-level shell library tracing, which remains STATBUS-353;
- weakening promotion authority, evidence requirements, structural harness
  doctrine, or paid-fleet admission controls.

## Ordered staffing plan

Use fresh agents sequentially so each receives a bounded problem and reports a
durable artifact before the next begins:

1. shell-boundary investigator/prototyper;
2. shell-boundary implementer;
3. adversarial shell/workflow reviewer;
4. Go extraction prototyper with the explicit stop gate;
5. Go implementer only if the prototype passes;
6. adversarial Go/history reviewer;
7. coordinator integration, ticket evidence, commit, and push.

No implementation agent may broaden its stage into later stages. Surprises cross
the ticket stop gate and return to the coordinator rather than being designed
around silently.

Read-only investigation evidence and prototypes belong under
`tmp/STATBUS-352-*`; the durable contract and final evidence belong in this
ticket.
<!-- SECTION:DESCRIPTION:END -->
