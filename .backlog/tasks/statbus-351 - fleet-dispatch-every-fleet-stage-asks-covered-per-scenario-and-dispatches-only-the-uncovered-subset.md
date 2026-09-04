---
id: STATBUS-351
title: >-
  fleet dispatch: every fleet stage asks `covered` per scenario and dispatches only the uncovered subset
status: To Do
assignee: []
created_date: '2026-09-04 07:18'
updated_date: '2026-09-04 07:24'
labels:
  - release
  - ci
  - cost
dependencies:
  - STATBUS-350
priority: medium
type: task
ordinal: 344000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
## The problem

The release chain (`release-fleet-orchestrator.yaml`) has ONE correct skip mechanism and uses it in only two of its four VM stages.

The correct mechanism is `./sb release covered <scenario> <sha>` (`cli/internal/release/coverage.go`, `DecideCoverage`, with the list rule in `cli/internal/release/sensitivity.go`): for one scenario it looks for green evidence at the target commit, else walks back through prior RC tags to the nearest one with evidence and diffs that tag against the target using `ops/release/upgrade-sensitive-paths.txt`. It is a Go library; the stable gate calls it directly and CI calls it through `./sb`. The bash job `decide-upgrade-sensitivity` is the only remaining second implementation of the rule, and this ticket deletes it. If no changed file is on the list the scenario is covered and need not run. The stable promotion gate (`checkInstallRecoveryHarnessGate`, `checkUpgradeArcHarnessGate`) runs exactly this walk for every scenario, so what the chain skips and what the gate demands agree.

Stage by stage today:

| stage | scenarios | skip mechanism today |
|---|---|---|
| 1 smoke install | 1 | `covered` (correct) |
| 2 smoke upgrade | 1 | `covered` (correct) |
| 4 install-recovery fleet | 15 | none: always dispatches all 15 |
| 5 upgrade-arc fleet | 32 | `decide-upgrade-sensitivity`: bash diff ONE hop to the previous RC tag, all-or-nothing |

Two consequences:

1. Stage 4 rents 15 VMs on every RC, including an RC that changed nothing the box executes. The stable gate would have accepted the prior RC's proof for every one of those scenarios.
2. Stage 5's one-hop diff is a different rule from the gate's walk. If the previous RC was itself skipped (no arc evidence at it), a one-hop "no sensitive change" answer skips the fleet while the gate's walk goes back further, finds sensitive changes since the last PROVEN tag, and refuses promotion. The chain then reports green for an RC the gate will not promote.

## What to do

1. Add `./sb release covered-subset <workflow> <sha>` (in `cli/cmd/release_covered.go`, next to `covered`): for the workflow's scenario domain at `<sha>` (`release.ScenariosAt`) run `DecideCoverage` for each scenario and print, one per line on stdout, the scenario names that are NOT covered. Exit 0 with an empty stdout when everything is covered, exit 0 with lines when some must run, exit 2 when any scenario's decision errored (name it on stderr), exit 64 on bad arguments. Same exit contract as `covered` (STATBUS-348).
2. In the orchestrator, stage 4 and stage 5 each get a "Decision point: which scenarios are uncovered?" step that runs `covered-subset` for its workflow, writes the list to the step summary (covered ones named as SKIPPED with the anchoring tag from the walk), and dispatches the harness with `dispatch-inputs: {"scenarios": "<the list>"}` only if the list is non-empty. `install-recovery-harness.yaml` already accepts `scenarios`; `upgrade-arc-harness.yaml` accepts its selector input the same way.
3. Delete `decide-upgrade-sensitivity` and its `sensitive` output from the orchestrator, and the top-of-file "UPGRADE-SENSITIVITY GATE" comment that describes it. Stage 5's `if:` keeps only the obsolete and upstream-result conditions.
4. Keep the harness's own rule that a run selecting zero scenarios fails red. The orchestrator never dispatches an empty subset, so that rule is never hit from the chain.
5. `doc/release-workflow-gates.md`: one paragraph stating that every VM stage decides per scenario with the same library the gate uses, and that `ops/release/upgrade-sensitive-paths.txt` is the single list both read.

## Why the fleets are still needed at all when the product changes

An RC that touches only `app/` skips every fleet and rides prior proof. That is correct: the dev canary (stage 3) never skips and is what proves the product itself. The fleets prove install, upgrade and recovery, and those only change when files on the sensitivity list change.

## Done when

- An RC whose diff against the last proven RC touches nothing on the sensitivity list runs the dev canary and nothing else; the step summary names every skipped scenario and the tag whose proof it rides.
- An RC that touches, for example, only `test/install-recovery/arcs/foo-arc.sh` dispatches the arc harness with exactly the scenarios `covered` says are uncovered.
- `GITHUB_TOKEN=... ./sb release stable` on such an RC reaches the same verdict as the chain, because both ran the same walk.
- `decide-upgrade-sensitivity` no longer exists.
<!-- SECTION:DESCRIPTION:END -->
