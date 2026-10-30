---
id: STATBUS-540
title: SSH access confirmation needs an explicit yes or no
status: In Progress
assignee: []
created_date: '2026-10-30T09:29:00Z'
updated_date: '2026-10-30T09:39:00Z'
labels:
  - setup
dependencies: []
priority: medium
type: bug
ordinal: 466204
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
### North Star
Confirming that someone can still log in is something the operator must actually do. The question cannot be passed with Enter.

### Zoom out
Stage 2 asks "Did that connect?" through ask_yes_no with default n, so the prompt shows [y/N] and an empty answer counts as no. That is safe (nothing changes) but lets the operator skip the check without thinking. Owner ruling 2026-10-30: this question has no default.

### Zoom in
Uganda run 2026-10-30, Stage 2: prompt "Did that connect? [y/N]".
Design: ask_yes_no accepts a default of "none": the hint is [y/n] and an empty answer re-asks ("Please type yes or no; this needs an explicit answer."). Only "Did that connect?" uses it. --non-interactive still answers yes. Every other question keeps its default.

### Closing review
- **Memory:** none. **Documentation:** ask_yes_no's comment. **Cleanup:** none.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 test/install-recovery/tests/setup-explicit-confirm-test.sh passes: the real ask_yes_no with default none, given an empty line then 'y', returns yes after re-asking once; given an empty line then 'n', returns no; its prompt shows [y/n]
- [x] #2 Stage 2's SSH access confirmation uses the explicit form; NON_INTERACTIVE=true still answers yes; every other prompt keeps its default and the existing setup tests pass
- [x] #3 The test fails against v2026.10.5's setup script and passes after (logs in tmp/); it runs in Harness Selftest
- [ ] #4 The next released setup, run on a box, shows the SSH access confirmation with [y/n] and re-asks when Enter is pressed
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Implemented in ad449113f: ask_yes_no accepts default 'none' (hint [y/n], empty answer re-asks with 'Please type yes or no; this needs an explicit answer.'); only ensure_remote_access's 'Did that connect?' uses it; NON_INTERACTIVE still answers yes and other prompts keep y/n. New setup-explicit-confirm-test.sh drives the real function through util-linux script(1) so the [y/n] prompt is observed (bash writes read -p prompts only to a tty); it covers empty+y -> yes with one re-ask, empty+n -> no, non-interactive yes, defaults preserved, and exactly one call site with none. Wired into harness-selftest.yaml. Red against v2026.10.5 (tmp/test-540-red.log): old hint [y/N] and 'Please answer yes or no.'. Green: tmp/test-540-green.log; all 19 setup-*.sh pass; bash -n clean. CI on ad449113f: Harness Selftest and Go Test green; app build & lint and Fast Tests were cancelled by later pushes to master, so reruns were requested against the same SHA.
<!-- SECTION:NOTES:END -->
