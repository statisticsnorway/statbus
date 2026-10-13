---
id: STATBUS-498
title: >-
  The CrowdSec firewall bouncer was installed inert while the stage ticked it
  green
status: Done
assignee: []
created_date: '2026-10-13 13:44'
updated_date: '2026-10-13 13:44'
labels:
  - install
  - hardening
  - security
dependencies: []
priority: high
type: bug
ordinal: 424204
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
FOUND 2026-10-13 reviewing the Uganda prepare run, Stage 4 (CrowdSec + UFW). The stage installed crowdsec and crowdsec-firewall-bouncer-nftables in ONE apt transaction, so the bouncer postinst ran before /etc/crowdsec/config.yaml existed and reported: "Error: while reading yaml file: open /etc/crowdsec/config.yaml: no such file or directory", "failed to create API key", and then said plainly that no api key was generated and that one must be created with cscli bouncers add. The stage never created one, and its check was only verify "Firewall bouncer installed" with pkg_installed. Result: a bouncer that is installed, enabled, running - and unable to ban a single IP, because the local API refuses it without a key - reported as a green tick. CrowdSec detects attacks; nothing remediates them. Owner decision 2026-10-13: fix it now.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 CrowdSec is installed in its own step, the stage waits for /etc/crowdsec/config.yaml, and it refuses to install a bouncer without that configuration. Checked by test/install-recovery/tests/setup-crowdsec-bouncer-order-test.sh assertions 1-3.
- [x] #2 When the bouncer package did not create an API key, the stage creates one and writes it into the bouncer configuration. Checked by assertion 4 plus reading the key-writing block.
- [x] #3 The stage fails rather than ticking green when the bouncer has no key or is not registered with the local API: two new verifications, "Firewall bouncer has an API key" and "Firewall bouncer registered with the local API". Checked by assertions 5 and 6.
- [ ] #4 The next real preparation shows a keyed, registered bouncer; to be recorded in STATBUS-497 (the Uganda rerun).
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
2026-10-13, fixed and evidenced by the coordinator directly (owner asked for it now rather than delegated). RED: STATBUS_SETUP_SCRIPT=<HEAD copy> bash test/install-recovery/tests/setup-crowdsec-bouncer-order-test.sh -> seven FAIL lines, rc=1 (no separate CrowdSec install, no wait, no key creation, no key/registration verifications). GREEN: seven PASS lines, rc=0; bash -n parses. Wired into .github/workflows/harness-selftest.yaml. Scope note: the upstream curl-to-bash repository setup on the line above is a separate question (STATBUS-499 filed for the decision), not changed here.

AC 4 (the bouncer observed keyed and registered on a real box) is deliberately deferred to STATBUS-497, which carries the Uganda rerun. This ticket is Done for the code, the ordering and the tests; 497 will report the observation.
<!-- SECTION:NOTES:END -->
