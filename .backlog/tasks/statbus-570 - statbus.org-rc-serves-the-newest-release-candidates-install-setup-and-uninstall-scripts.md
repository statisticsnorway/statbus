---
id: STATBUS-570
title: >-
  statbus.org/rc/ serves the newest release candidate's install, setup and
  uninstall scripts
status: To Do
assignee: []
created_date: '2026-11-04T08:19:00Z'
labels:
  - installer
  - release
dependencies: []
priority: medium
ordinal: 486204
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
North Star: an operator testing a candidate types one short command, curl -fsSL https://statbus.org/rc/install.sh | bash, and gets the newest candidate's own installer. statbus.org/install.sh keeps serving the latest stable (STATBUS-505).

### Zoom out
GitHub has a stable 'latest' download link but none for the newest prerelease, so testers paste a long tagged URL plus --version (the manual-box guide does this). Owner decision 2026-11-04: paths /rc/install.sh, /rc/setup.sh, /rc/uninstall.sh. A query string (?prerelease) was rejected: zsh expands an unquoted ?, and Caddy has no fixed target to redirect to.

### Zoom in
Each /rc/ path serves a small fixed resolver from niue (it never changes per release): it finds the newest v*-rc.* tag from the GitHub releases list with install.sh's own ordering, downloads that release's asset and runs it with bash, passing the operator's arguments; install also passes --version <tag>. The resolvers are versioned in the repository; niue's Caddy serves the files (one-time edit, needs root and the owner's go).
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 The resolvers for install, setup and uninstall are in the repository, each picks the newest v*-rc.* release (cross-month order included), runs that release's own script with the operator's arguments, and refuses with a clear message when no candidate is published; a test proves it with a GitHub double
- [ ] #2 On niue, statbus.org/rc/install.sh, /rc/setup.sh and /rc/uninstall.sh serve the resolvers (backup, caddy validate, reload); from outside, each returns 200 and running /rc/install.sh --help style banner names the newest candidate
- [ ] #3 doc/DEPLOYMENT.md and the manual-box guide use the /rc/ form for candidates
<!-- AC:END -->
