---
id: STATBUS-387
title: Every installer rerun command works from the operator's current directory and preserves the chosen options
status: In Progress
assignee: []
created_date: '2026-09-24 16:42'
updated_date: '2026-09-24 18:40'
labels:
  - release-bug
  - install
dependencies: []
priority: high
type: bug
ordinal: 1
---

## Status 2026-09-24

**In Progress.** `e2e2f3ee2`, `373d15fc3`: `cli/cmd/install_operator_rerun_test.go::TestEveryInstallerRerunHintUsesSavedCommand` checks saved options (#1-2 partly), but the named scan and stable/prerelease/unattended matrix are absent. #3's `4-install-port-80-taken.sh` is authored, real-VM paste proof pending. **Remaining:** cover every rerun path and invocation mode, then paste the printed command from home on a VM.

Baseline: `origin/master` at `373d15fc3`. Criterion disposition and remaining positive targets are above; the acceptance criteria below remain authoritative. An authored but unrun VM scenario is **proof pending**, not met.

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Every rerun instruction prints a complete, directory-independent install command. The command preserves the original channel and unattended options, including `--channel prerelease`, so pasting it from the operator's current directory repeats the same requested installation.

## Evidence, 2026-09-24

The Finland output printed `./sb install`, and that command failed from the operator's home directory because the executable was under `~/statbus` (`/Users/jhf/ssb/statbus/tmp/finland-transcript-actual.txt:16-36,74-81`). Current directory-dependent strings originate in `install.sh:5`, `cli/cmd/root.go:122`, and `cli/cmd/install.go:534-535` at master `7a9cf707e`.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 `new: test/install-rerun-messages.sh` scans every operator-facing rerun path and asserts a complete directory-independent command rather than `./sb install`.
- [ ] #2 `new: cli/cmd/install_rerun_test.go::TestRerunCommandPreservesInvocationOptions` covers stable, `--channel prerelease`, and unattended invocations and observes the same options in each printed command.
- [ ] #3 `new: test/install-recovery/scenarios/4-install-port-80-taken.sh` pastes the printed prerelease unattended rerun command from the home directory and reaches the same selected installation.
<!-- AC:END -->
