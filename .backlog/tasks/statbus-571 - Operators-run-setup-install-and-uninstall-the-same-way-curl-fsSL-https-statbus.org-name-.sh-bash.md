---
id: STATBUS-571
title: >-
  Operators run setup, install and uninstall the same way: curl -fsSL
  https://statbus.org/<name>.sh | bash
status: In Progress
assignee: []
created_date: '2026-11-04T10:27:00Z'
updated_date: '2026-11-06T17:21:00Z'
labels:
  - installer
  - setup
dependencies: []
priority: high
type: enhancement
ordinal: 490204
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
North Star: one command shape for every operator script, always the current release, safe to pipe.

### Zoom out
Owner decision 2026-11-04: pipe everywhere (option A). A downloaded copy goes stale; piping always runs the release statbus.org (stable) or statbus.org/rc/ (candidate) serves. The docs mixed three forms (pipe; download + chmod + ./setup.sh; download + bash setup.sh) because setup could not be piped.

### Zoom in
Found 2026-11-04: `curl -fsSL https://statbus.org/setup.sh | bash` does nothing (main runs only when BASH_SOURCE[0] == $0, which a pipe never satisfies), and setup reads its answers from stdin, which is the script itself when piped. Piping is safe when each script (1) reads answers from the terminal and (2) is one block bash reads completely before running anything, so a download cut short runs nothing.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Piped (`cat script | bash`), each of setup, install and uninstall runs: setup reaches main, install parses its arguments, uninstall asks its questions on the terminal and accepts the answers given there
- [x] #2 Each script cut short at any point runs nothing: bash exits 2 with no output from the script
- [x] #3 setup run piped without a terminal and without --non-interactive refuses, naming --non-interactive and its config file, instead of reading answers from the pipe
- [x] #4 README, DEPLOYMENT, setup-ubuntu-lts.md and the manual-box guide show only the piped form, statbus.org for stable and statbus.org/rc/ for candidates
- [ ] #5 [Owner] On the manual box with the next candidate, setup, install and uninstall are each run piped from statbus.org/rc/ and finish normally
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
- **2026-11-04, `684444096`.** piped-scripts-test.sh (real scripts, pty as the terminal): red before (tmp/piped-scripts-red.log: piped setup ran nothing; every script ran when cut short, e.g. install at lines 15/40/120 exit 0; setup with no terminal exit 0), green after (tmp/piped-scripts-green.log): piped setup reaches main, piped install parses args, piped uninstall answers four questions on the terminal and finishes; each script cut at 7 points exits 2 with no output; setup with no terminal refuses naming --non-interactive.
- **Change:** each script is one `{ ... exit; }` block (opening brace on line 2, so LINENO in install.sh's ERR trap still names the file line, checked). setup: main runs when executed or piped and returns when sourced (tests source it); interactive runs read from /dev/tty when stdin is not a terminal, refuse without one. All automated callers (LXD base, vm-bootstrap, test-hardening) pass --non-interactive.
- **Regression:** setup-*.sh, install-*.sh, fresh-installer, release-script-stamp (banner_of closes the block) green; setup-crowdsec-bouncer-key and setup-explicit-confirm give identical results to HEAD on macOS (pre-existing macOS-only failures: script -c; they run green on Linux CI); go test ./cmd green (install_rerun_test closes the block); shellcheck: same 3 pre-existing setup warnings as HEAD.
- **AC4:** README, DEPLOYMENT (removal, setup, quick install), setup-ubuntu-lts.md (stable, rc, pinned asset URL; options after bash -s --), hetzner-bootstrap.md, setup's header comment and the manual-box guide show only the piped form. Pinned setup is the release asset URL (first carried by v2026.10.1).

2026-11-06 17:20 UTC: the piped form ran on Uganda (curl -fsSL https://statbus.org/rc/setup.sh | bash -s -- --only-stages ...) with v2026.11.1-rc.15 and completed. The stable v2026.11.0 setup did nothing when piped (its main guard predates 684444096), so a piped stable setup works only once this release is stable (tmp/583-piped-setup-stable-vs-rc15.log).
<!-- SECTION:NOTES:END -->
