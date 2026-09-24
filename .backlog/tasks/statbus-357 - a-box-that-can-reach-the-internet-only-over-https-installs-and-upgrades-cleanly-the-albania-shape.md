---
id: STATBUS-357
title: A box with outbound HTTPS-only policy installs and upgrades successfully
status: To Do
assignee: []
created_date: '2026-09-07 07:02'
updated_date: '2026-09-24 18:47'
labels:
  - harness
  - install
  - upgrade
  - fidelity
dependencies:
  - STATBUS-363
priority: medium
type: task
ordinal: 50
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
The paid VM proof applies the production Ubuntu hardening, blocks external TCP port 80 while preserving Docker-published loopback health traffic, installs the baseline, and upgrades to the candidate using ordinary operator paths. It remains on demand until the real-VM NAT behavior is proven. After that proof and a deliberate HTTP mutation control pass, it joins the default selected set.

## Evidence, 2026-09-24

The current scenario is explicitly on demand through `HARNESS_SKIP_DEFAULT` (`test/install-recovery/scenarios/0-https-only-egress.sh:2-10` at master `7a9cf707e`). Its firewall and mutation contract is in `test/install-recovery/scenarios/0-https-only-egress.sh:18-96`, while Ubuntu 26.04 selection is owned by `test/install-recovery/lib/vm-bootstrap.sh:1313-1314`, all at master `7a9cf707e`. Product external fetches use HTTPS in the bootstrap (`install.sh:624-685`), release-manifest download (`cli/internal/upgrade/github.go:205`), and registry base URL (`cli/internal/upgrade/ghcr.go:14`), all at master `7a9cf707e`. No line-specific primary Albania record or checked-in Albania workaround has been located, so earlier Albania historical assertions are withdrawn rather than treated as evidence.

The proof identity is `STATBUS-357-https-only-nat-1`. Its evidence file is `new: test/install-recovery/evidence/STATBUS-357-https-only-nat-1.md`, which records candidate tag, harness run URL, Ubuntu image, firewall rules, original-destination NAT observation, install result, and upgrade result.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 `new: test/install-recovery/scenarios/0-https-only-egress.sh` run `STATBUS-357-https-only-nat-1` first proves on a real Ubuntu 26.04 VM that the corrected original-destination exemption preserves the Docker-published loopback health path while external TCP/80 is rejected.
- [ ] #2 `new: test/install-recovery/tests/https-only-egress-mutation-test.sh` introduces `http://example.com/statbus-http-egress-mutation` and observes the scenario fail while naming that URL.
- [ ] #3 `new: test/install-recovery/evidence/STATBUS-357-https-only-nat-1.md` records a successful baseline install and candidate upgrade under the corrected real-VM rule.
- [ ] #4 After criteria #1-#3, `test/install-recovery/scenarios/0-https-only-egress.sh` removes `HARNESS_SKIP_DEFAULT`, and `new: test/install-recovery/tests/https-only-egress-selection-test.sh` observes the scenario in `run.sh --print-selected`.
<!-- AC:END -->
