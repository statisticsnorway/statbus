---
id: STATBUS-585
title: >-
  ./sb install on a development box with Docker Desktop says Docker's storage is
  not measured and continues
status: To Do
assignee: []
created_date: '2026-11-06T17:28:00Z'
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
- [ ] #1 With CADDY_DEPLOYMENT_MODE=development and a reported Docker root that does not exist on the host, install prints one line saying Docker's storage is inside its VM and is not measured, and continues
- [ ] #2 In standalone and private modes the refusal is unchanged
- [ ] #3 Go tests cover both modes, red before and green after
- [ ] #4 No test writes into the project's real tmp/install-last-run-output.txt; the test that did is found and fixed
<!-- AC:END -->
