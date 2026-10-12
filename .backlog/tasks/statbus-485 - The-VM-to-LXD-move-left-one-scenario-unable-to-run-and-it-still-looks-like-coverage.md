---
id: STATBUS-485
title: >-
  The 0-https-only-egress scenario cannot run on the LXD backend and is parked
  where no gate sees it
status: In Progress
assignee: []
created_date: '2026-10-12 19:26'
updated_date: '2026-10-12 19:30'
labels:
  - ci
  - lxd
  - harness
  - release
dependencies: []
priority: high
type: bug
ordinal: 411204
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
NORTH STAR: every install-recovery scenario the repository ships runs on the backend that ships today (LXD), and 0-https-only-egress is back in the default set with a recorded green run.

DISCOVERY (state at fc95698cf^, test/install-recovery/):
- lxd/run-forks.sh:89-93 builds a shadow tree where lib/lxd-backend.sh is symlinked over lib/vm-bootstrap.sh. Scenarios are unchanged, so any function defined only in vm-bootstrap.sh is missing under LXD.
- lib/vm-bootstrap.sh:1376-1426 defines apply_https_only_egress: an nft table that rejects TCP/80 to public IPv4/IPv6 while exempting loopback and private ranges, then probes that IPv4 and IPv6 are refused (curl rc=7).
- lib/lxd-backend.sh did not define it, although it already had the VM_EXEC/VM_ROOT_EXEC primitives the function uses (lines 1043-1044, via lxc exec).
- scenarios/0-https-only-egress.sh:14 sets HARNESS_HTTPS_ONLY_EGRESS=1, and scenarios/0-happy-upgrade.sh:129 then calls apply_https_only_egress. Under LXD the scenario would die with command-not-found.
- No gate noticed: the scenario carries HARNESS_SKIP_DEFAULT (line 10), which run.sh:33-34 and lxd/run-forks.sh:104 skip. tests/https-only-egress-test.sh:193 asserts that marker is present, and tests/scenario-selection-test.sh asserts the scenario is NOT in the default set.
- History (git log --follow): added in the default set 2026-09-23 (feef56330), made on-demand 2026-09-24 (fe4a769a7), rejoined (61ece22d1), on-demand again in the next commit (684945e11). test/install-recovery/evidence/ does not exist, so no green real run was ever recorded.

WHY IT MATTERS: a parked scenario that cannot run still looks like coverage. The HTTPS-only egress guarantee (STATBUS-357) is currently tested by nothing that executes.

PLAN:
1. Port apply_https_only_egress to lib/lxd-backend.sh. Landed in fc95698cf.
2. Run the offline contract and mutation tests against both backends. Landed in fc95698cf; red-then-green evidence still to record.
3. Run the scenario once as an on-demand LXD fork against the previous RC (v2026.10.0-rc.20) and write the STATBUS-357 evidence file.
4. Remove HARNESS_SKIP_DEFAULT and flip the selection tests so the scenario is in the default set.

RELATED: STATBUS-357 owns the HTTPS-only scenario. Its AC 2-4 name the mutation test, evidence file and selection test reused here. STATBUS-425 M4 removes the last Hetzner VM from the gate. It follows this ticket and is tracked there.

BACKGROUND (not criteria): tmp/gate-map-2026-10-12.md, tmp/walk-2026-10-12-grounding.md.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 lib/lxd-backend.sh defines apply_https_only_egress with the same nft rules and IPv4/IPv6 refusal probes as lib/vm-bootstrap.sh. Checked by: test/install-recovery/tests/https-only-egress-test.sh passes for both backends at HEAD and fails for lxd-backend at fc95698cf^. Both outputs are recorded in this ticket.
- [ ] #2 test/install-recovery/tests/https-only-egress-mutation-test.sh turns the contract red on both backends for each mutation: missing IPv4 rule, widened rule (the failure names the refused URL), missing IPv6 rule, and an exempt set without 172.16.0.0/12. Checked by running it; the output is recorded in this ticket.
- [ ] #3 One real on-demand LXD fork of scenarios/0-https-only-egress.sh against v2026.10.0-rc.20 passes and writes test/install-recovery/evidence/STATBUS-357-https-only-nat-1.md. The file records the candidate tag, run URL, Ubuntu image, nft rules as listed, docker-proxy health result, install result and upgrade result. Checked by: the file is committed and the run URL resolves to a green run.
- [ ] #4 scenarios/0-https-only-egress.sh no longer contains HARNESS_SKIP_DEFAULT. Checked by: run.sh --print-selected lists 0-https-only-egress, the selection test (STATBUS-357 AC 4) asserts this, and tests/https-only-egress-test.sh and tests/scenario-selection-test.sh no longer require on-demand.
<!-- AC:END -->

## Definition of Done
<!-- DOD:BEGIN -->
- [ ] #1 AC 1-4 checked, each with its evidence (test output, evidence file path, run URL) recorded in this ticket
- [ ] #2 The scenario runs in the default fault set of the next release candidate's gate
<!-- DOD:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
2026-10-12: steps 1-2 landed in fc95698cf (port, two-backend contract, mutation test). Steps 3-4 and AC evidence remain.
<!-- SECTION:NOTES:END -->
