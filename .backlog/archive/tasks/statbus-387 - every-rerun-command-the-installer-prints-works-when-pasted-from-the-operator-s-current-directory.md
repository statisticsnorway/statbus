---
id: STATBUS-387
title: >-
  Every installer rerun command works from the operator's current directory and
  preserves the chosen options
status: Done
assignee: []
created_date: '2026-09-24 16:42'
updated_date: '2026-09-29 11:54'
labels:
  - release-bug
  - install
dependencies: []
priority: high
type: bug
ordinal: 1
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Every rerun instruction prints a complete, directory-independent install command. The command preserves the original channel and unattended options, including `--channel prerelease`, so pasting it from the operator's current directory repeats the same requested installation.

## Evidence, 2026-09-24

The Finland output printed `./sb install`, and that command failed from the operator's home directory because the executable was under `~/statbus` (`/Users/jhf/ssb/statbus/tmp/finland-transcript-actual.txt:16-36,74-81`). Current directory-dependent strings originate in `install.sh:5`, `cli/cmd/root.go:122`, and `cli/cmd/install.go:534-535` at master `7a9cf707e`.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 `cli/cmd/install_command_literal_test.go::TestNoGoLiteralTellsTheOperatorToRunABareInstall` in `go test ./...` (replacing `test/install-rerun-messages.sh`, rewritten 2026-09-29 after review tmp/review-rerun-hints.md) finds no operator-facing string under cli/ or echo in install.sh containing a bare relative `./sb install`; install-time hints use the saved install.sh command, and upgrade/recovery hints use one local, version-preserving command for the box's checkout, never the stable curl installer, so the channel and version are preserved.
- [x] #2 `new: cli/cmd/install_rerun_test.go::TestRerunCommandPreservesInvocationOptions` covers stable, `--channel prerelease`, and unattended invocations and observes the same options in each printed command.
- [x] #3 `new: test/install-recovery/scenarios/4-install-port-80-taken.sh` pastes the printed prerelease unattended rerun command from the home directory and reaches the same selected installation.
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Audit after v2026.09.3 (2026-09-29): Done in v2026.09.3 (d76ff7d3a, e2e2f3ee2). AC2 is green in Go Test 36503468493, and AC3 passed as 4-install-port-80-taken in rc.17 LXD fleet 36506437069. AC1's test/install-rerun-messages.sh passed when run by hand on the v2026.09.3 tree, but no workflow runs it.

Coordinator 2026-09-29: kept In Progress. AC1's scan (test/install-rerun-messages.sh) passes by hand but no workflow runs it, and review (tmp/review-selftest-runid.md C1) found 6 bare './sb install' rerun hints outside its 5-file scope: install_refusal.go:111,129; install_upgrade.go:362,406,423; db.go:1023. Fix and a repo-wide scanner in CI are in progress on fix/selftest-runid.

Done 2026-09-29: merge 367966083 (reviews tmp/review-selftest-runid.md, tmp/review-rerun-hints.md BLOCK, tmp/review-rerun-hints-2.md MERGE). AC1 proven by cli/cmd/install_command_literal_test.go::TestNoGoLiteralTellsTheOperatorToRunABareInstall in Go Test 36564358788 (success) at 367966083. Install-time hints keep the saved install.sh command; upgrade/recovery hints and the direct ./sb install fallback use 'cd <checkout> && ./sb install', which preserves channel and version.
<!-- SECTION:NOTES:END -->

## Status 2026-09-24

**In Progress.** `e2e2f3ee2`, `373d15fc3`: `cli/cmd/install_operator_rerun_test.go::TestEveryInstallerRerunHintUsesSavedCommand` checks saved options (#1-2 partly), but the named scan and stable/prerelease/unattended matrix are absent. #3's `4-install-port-80-taken.sh` is authored, real-VM paste proof pending. **Remaining:** cover every rerun path and invocation mode, then paste the printed command from home on a VM.

Baseline: `origin/master` at `373d15fc3`. Criterion disposition and remaining positive targets are above; the acceptance criteria below remain authoritative. An authored but unrun VM scenario is **proof pending**, not met.
