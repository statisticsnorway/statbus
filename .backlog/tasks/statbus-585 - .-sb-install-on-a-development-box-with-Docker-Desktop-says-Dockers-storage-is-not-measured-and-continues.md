---
id: STATBUS-585
title: >-
  ./sb install on a development box with Docker Desktop says Docker's storage is
  not measured and continues
status: Done
assignee: []
created_date: '2026-11-06T17:28:00Z'
updated_date: '2026-11-06T18:18:00Z'
labels:
  - bug
dependencies: []
priority: medium
ordinal: 497204
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Reported by hibiscus 2026-11-06 (owner request 17:22, decision 17:26; evidence /Users/jhf/ssb/statbus/tmp/566-4g/install-log.md). On macOS with Docker Desktop, ./sb install refuses at preflight: 'cannot check disk space at Docker storage: Docker root unavailable'. docker info reports DockerRootDir=/var/lib/docker, which exists only inside Docker's VM; diskpolicy.DockerRoot os.Stat()s it on the host (cli/internal/diskpolicy/policy.go:186-189, called from cli/cmd/install.go). Owner: no skip flag. Mac is not a supported target; this is for development use. Related: tmp/install-last-run-output.txt on that dev box held lines from test fixtures (github.example, does-not-resolve.invalid, fixture-missing-ref), so a test writes into the real install diagnostics file.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 With CADDY_DEPLOYMENT_MODE=development and a reported Docker root that does not exist on the host, install prints one line saying Docker's storage is inside its VM and is not measured, and continues
- [x] #2 In standalone and private modes the refusal is unchanged
- [x] #3 Go tests cover both modes, red before and green after
- [x] #4 No test writes into the project's real tmp/install-last-run-output.txt; the test that did is found and fixed
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Owner 2026-11-06 18:17: fix the test-log inconsistency now. Commit above. diskpolicy.DockerRootReporting: development + VM-only root -> one line, continue; standalone/private refuse (TestDockerRootInsideDockerDesktopVM, red tmp/585-red.log, green tmp/585-green.log). install-git-errors-test.sh appended fixture lines to the repository's tmp/install-last-run-output.txt (red tmp/585-test-log-red.log); now runs from a scratch checkout under its HOME and asserts the repository file is unchanged (green tmp/585-test-log-green.log).
<!-- SECTION:NOTES:END -->
