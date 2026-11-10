---
id: STATBUS-540
title: SSH access confirmation needs an explicit yes or no
status: Done
assignee: []
created_date: '2026-10-30T09:29:00Z'
updated_date: '2026-11-10T09:17:00Z'
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
- [x] #4 The next released setup, run on a box, shows the SSH access confirmation with [y/n] and re-asks when Enter is pressed
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Implemented in ad449113f: ask_yes_no accepts default 'none' (hint [y/n], empty answer re-asks with 'Please type yes or no; this needs an explicit answer.'); only ensure_remote_access's 'Did that connect?' uses it; NON_INTERACTIVE still answers yes and other prompts keep y/n. New setup-explicit-confirm-test.sh drives the real function through util-linux script(1) so the [y/n] prompt is observed (bash writes read -p prompts only to a tty); it covers empty+y -> yes with one re-ask, empty+n -> no, non-interactive yes, defaults preserved, and exactly one call site with none. Wired into harness-selftest.yaml. Red against v2026.10.5 (tmp/test-540-red.log): old hint [y/N] and 'Please answer yes or no.'. Green: tmp/test-540-green.log; all 19 setup-*.sh pass; bash -n clean. CI on ad449113f: Harness Selftest and Go Test green; app build & lint and Fast Tests were cancelled by later pushes to master, so reruns were requested against the same SHA.

AC4 verified 2026-11-02 on statbus-manual (freshly rebuilt Ubuntu 26.04) with released v2026.11.0 setup.sh (banner 'StatBus: v2026.11.0'). Session log tmp/statbus-manual-session.log lines 1673-1675: 'Did that connect? [y/n]:' + Enter -> 'Please type yes or no; this needs an explicit answer.' and the question again; a real second-terminal ssh as statbus succeeded, answered y, setup completed all 9 stages (line 2497 'Setup Complete!').

2026-11-10 09:17 UTC Uganda (statbus.ubos.org, Ubuntu 26.04, setup v2026.11.3), owner ran --only-stages "base-system security-tools": base-system verified (etckeeper installed and initialised, bash history, C.UTF-8 and en_US.UTF-8 locales); security-tools verified: CrowdSec running, firewall bouncer has an API key, is registered with the local API ('Bouncer statbus-firewall-bouncer is registered') and running, SSHD collection installed, UFW active, OpenSSH allowed, SSH port 713 allowed, HTTP, HTTPS and PostgreSQL allowed. Summary: 'No follow-up from this run.' Earlier the same morning: auto-updates stage, Docker in the nightly updates (STATBUS-583). (The SSH access confirmation lives in ssh-hardening, not rerun here; AC4 stands on its earlier evidence.)
<!-- SECTION:NOTES:END -->
