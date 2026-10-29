---
id: STATBUS-535
title: >-
  ghcr.io login in CI does not retry; one DNS timeout fails an image build and
  the upgrade arcs
status: In Progress
assignee: []
created_date: '2026-10-29T23:26:00Z'
updated_date: '2026-10-29T23:27:00Z'
labels:
  - ci
  - release
dependencies: []
priority: high
type: bug
ordinal: 461204
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
## North Star
A release gate verdict reflects the product, not a single transient network miss on a CI runner.

## Zoom out
Every image build, release and arc run logs in to ghcr.io. docker/login-action and bare docker login try once, so a resolver timeout on one of dozens of matrix jobs fails the whole gate, and then other jobs spend their full wait budget.

## Zoom in
v2026.10.5-rc.02: Images run 40967128256 (fixture branch test/upgrade-arc-working-fixed-migration) failed at login with 'lookup ghcr.io on 127.0.0.53:53: i/o timeout'. The proxy arm64 build was never pushed, and Upgrade Arc Harness run 40966999495 waited 40 minutes for statbus-*:30b0a7b8 before failing.

## Closing review
No memory needed. The workflow step comments document why the retry is inline (fixture branches run master's workflows over an older tree, STATBUS-236). Cleanup: none.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 test/ci-ghcr-login-retry-test.sh passes: each real ghcr login step in images.yaml, release.yaml, fast-tests.yaml and the arc image wait logs in after 2 fake failures and fails after 5
- [x] #2 test/ci-ghcr-login-retry-test.sh reports no docker/login-action left in those workflows; the retry is inline, so fixture branches inherit it
- [x] #3 test/ci-ghcr-login-retry-test.sh fails on the pre-fix workflows, passes after, and runs in Harness Selftest
- [ ] #4 The next RC's Upgrade Arc Harness completes its image wait and passes
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Red on pre-fix workflows: 'FAIL: images.yaml step check logs in to ghcr.io without retrying' (tmp/test-ghcr-login-red.log). Green after: 9 login steps PASS (tmp/test-ghcr-login-green.log). The rarely used off-master arc base check keeps a single login with its own explicit error.
<!-- SECTION:NOTES:END -->
