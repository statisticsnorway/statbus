---
id: STATBUS-570
title: >-
  statbus.org/rc/ serves the newest release candidate's install, setup and
  uninstall scripts
status: Done
assignee: []
created_date: '2026-11-04T08:19:00Z'
updated_date: '2026-11-04T10:03:00Z'
labels:
  - installer
  - release
dependencies: []
priority: medium
type: feature
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
- [x] #1 The resolvers for install, setup and uninstall are in the repository, each picks the newest v*-rc.* release (cross-month order included), runs that release's own script with the operator's arguments, and refuses with a clear message when no candidate is published; a test proves it with a GitHub double
- [x] #2 On niue, statbus.org/rc/install.sh, /rc/setup.sh and /rc/uninstall.sh serve the resolvers (backup, caddy validate, reload); from outside, each returns 200 and running /rc/install.sh --help style banner names the newest candidate
- [x] #3 doc/DEPLOYMENT.md and the manual-box guide use the /rc/ form for candidates
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
- **AC1 (2026-11-04):** resolvers in ops/niue/rc/ (install, setup, uninstall; one shared body). rc-resolver-test.sh: first run red on a real defect (EXIT trap read a function-local temp path: 'script: unbound variable', tmp/rc-resolver-1.log), green after (tmp/rc-resolver-green.log): newest of v2026.10.6-rc.12/v2026.11.1-rc.05/rc.06 plus stable tags is rc.06; install gets --version rc.06 plus the operator's args; no candidate refuses naming statbus.org/install.sh; temp script removed. Against real GitHub: install banner 'StatBus installer v2026.11.1-rc.06', setup 'StatBus: v2026.11.1-rc.06'. CI: harness-selftest step.

- **Design change (owner, 2026-11-04):** Caddy redirects /rc/<name>.sh to ops/rc/<name>.sh on master instead of hosting copies on niue; one rule, nothing to keep in sync. Master is on the operator path for this lookup only; the code it runs is the candidate's tagged script. Resolvers moved ops/niue/rc -> ops/rc (`eaeb592a7`).
- **AC2 (2026-11-04):** root on niue (owner granted). Backup /etc/caddy/Caddyfile.bak-570-20261104T100218Z; exact-text edit adds `@rc path_regexp ^/rc/(install|setup|uninstall)\.sh$` -> raw master ops/rc/{re.rc.1}.sh 302; caddy validate 'Valid configuration'; reload; caddy active (tmp/570-niue-apply.log). The same block was first proven in a caddy:2.11 container. From outside: /rc/install.sh, /rc/setup.sh, /rc/uninstall.sh 302 to master ops/rc/ (200); /rc/other.sh, /install.sh, /setup.sh, /uninstall.sh, / unchanged. `curl -fsSL https://statbus.org/rc/install.sh | bash -s -- --bogus` prints 'StatBus installer v2026.11.1-rc.06'; /rc/setup.sh --help prints 'StatBus: v2026.11.1-rc.06'. Staged /tmp files removed.
- **AC3:** DEPLOYMENT.md and README show /rc/ for candidates and statbus.org for stable (DEPLOYMENT no longer downloads from raw master) (`eaeb592a7`); manual-box guide uses /rc/ (`33592bba8`), guide test red (tmp/manual-box-guide-rc-red.log) then green with a gh double that applies the real jq filter.
<!-- SECTION:NOTES:END -->
