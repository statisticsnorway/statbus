---
id: STATBUS-573
title: >-
  Setup installs the operator's SSH keys even when GitHub answers slowly or not
  at all for a moment
status: In Progress
assignee: []
created_date: '2026-11-06T10:07:00Z'
updated_date: '2026-11-06T10:08:00Z'
labels: []
dependencies: []
priority: high
ordinal: 492204
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Setup's service-account and SSH stages install the login keys of the GitHub users in GITHUB_USERS from https://github.com/<user>.keys. One fetch answering nothing made setup carry on with no key for the account; only the later verifications failed. Observed: rc.12 gate, Test Smoke 42043619999 (Ramp hardened LXD fleet host, 2026-11-05 14:19, GitHub degraded): 'No keys returned from https://github.com/jhf.keys', 0 keys installed, Setup finished WITH PROBLEMS.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 A GitHub key fetch that fails or times out is retried a bounded number of times, and the key is installed once GitHub answers
- [x] #2 When GitHub stays unreachable, setup names it ('Could not reach GitHub for the SSH keys of <user> ... Run this script again when GitHub answers.') and the run ends WITH PROBLEMS
- [x] #3 A GitHub user who has no ED25519 key is told so, without retrying
- [ ] #4 The rc.13 gate's hardened LXD host setup installs the key
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Test first: test/install-recovery/tests/setup-github-keys-retry-test.sh (curl double exits 28 with nothing on stdout, like the real curl on timeout). Red against the current setup (tmp/setup-github-keys-retry-red.log): 1 attempt, 0 keys, rc=0, nothing recorded. Green after fetch_github_keys (4 bounded attempts, growing pause) and the named failure recorded via verify (tmp/setup-github-keys-retry-green.log). setup-remote-access-gate-test and the other setup tests still pass. Wired into Harness Selftest. AC4 waits for the rc.13 gate.
<!-- SECTION:NOTES:END -->
