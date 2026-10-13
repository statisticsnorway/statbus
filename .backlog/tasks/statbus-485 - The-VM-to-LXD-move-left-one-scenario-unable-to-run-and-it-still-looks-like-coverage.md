---
id: STATBUS-485
title: >-
  The 0-https-only-egress scenario cannot run on the LXD backend and is parked
  where no gate sees it
status: In Progress
assignee: []
created_date: '2026-10-12 19:26'
updated_date: '2026-10-13 12:44'
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
- [x] #1 lib/lxd-backend.sh defines apply_https_only_egress with the same nft rules and IPv4/IPv6 refusal probes as lib/vm-bootstrap.sh. Checked by: test/install-recovery/tests/https-only-egress-test.sh passes for both backends at HEAD and fails for lxd-backend at fc95698cf^. Both outputs are recorded in this ticket.
- [x] #2 test/install-recovery/tests/https-only-egress-mutation-test.sh turns the contract red on both backends for each mutation: missing IPv4 rule, widened rule (the failure names the refused URL), missing IPv6 rule, and an exempt set without 172.16.0.0/12. Checked by running it; the output is recorded in this ticket.
- [x] #3 One real on-demand LXD fork of scenarios/0-https-only-egress.sh against v2026.10.0-rc.20 passes and writes test/install-recovery/evidence/STATBUS-357-https-only-nat-1.md. The file records the candidate tag, run URL, Ubuntu image, nft rules as listed, docker-proxy health result, install result and upgrade result. Checked by: the file is committed and the run URL resolves to a green run.
- [x] #4 scenarios/0-https-only-egress.sh no longer contains HARNESS_SKIP_DEFAULT. Checked by: run.sh --print-selected lists 0-https-only-egress, the selection test (STATBUS-357 AC 4) asserts this, and tests/https-only-egress-test.sh and tests/scenario-selection-test.sh no longer require on-demand.
- [x] #5 The two offline tests (tests/https-only-egress-test.sh and tests/https-only-egress-mutation-test.sh) are executed by the Harness Selftest workflow, so breaking the rule turns CI red instead of only a hand run. Checked by: the workflow log lists both tests on a push touching test/install-recovery/**. Today it runs neither (found 2026-10-12).
<!-- AC:END -->

## Definition of Done
<!-- DOD:BEGIN -->
- [ ] #1 AC 1-4 checked, each with its evidence (test output, evidence file path, run URL) recorded in this ticket
- [ ] #2 The scenario runs in the default fault set of the next release candidate's gate
<!-- DOD:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
2026-10-12: steps 1-2 landed in fc95698cf (port, two-backend contract, mutation test). Steps 3-4 and AC evidence remain.

Steps 1+2 done in fc95698cf (2026-10-12). TEST DEFECT FOUND AND FIXED: the contract test sourced vm-bootstrap.sh at top level, so its apply_https_only_egress leaked into the lxd-backend subshell and the contract was FALSE-GREEN for lxd-backend before any port. Both tests now unset -f apply_https_only_egress before sourcing each backend. Also fixed the mutation test's URL-naming probe, which aborted under set -e on its expected red (now '|| true' with the grep still asserting the URL). RED (port absent): contract 'line 141: apply_https_only_egress: command not found / FAIL: the HTTPS-only contract does not hold for lxd-backend'. Mutation: 'vm-bootstrap ok; FAIL: missing IPv4 nft rule [lxd-backend] failed for the wrong reason: command not found'. GREEN: both PASS on both backends (four mutations plus the URL-naming check). CI for fc95698cf at job level: Harness Selftest 38297872803 success, Go Test 38297872863 (lint+test) success, app build & lint 38297872683 success, CodeQL 38297872753 success. GAP: the harness-selftest log has no mention of https-only, so CI does NOT run these two offline tests. Wiring them in belongs with AC 5. No Fast Tests run was triggered for this SHA (path filter).

2026-10-13 (coordinator, before a planned divert): state is AC 1-2 done, AC 3-6 open. Plan A was agreed (machinery before candidate), so AC 3's single host run is taken on the settled harness, after STATBUS-425 M4, together with the candidate work. The worker that landed steps 1-2 also found that the offline contract had been FALSE-GREEN for the LXD backend (the VM backend's function leaked into the LXD subshell; both tests now unset it before sourcing each backend) and that CI runs neither offline test, which is why AC 6 exists.

2026-10-13 (worker, AC 3/4/5 session). Ticket AC numbers: #3 real run, #4 marker removed, #5 offline tests in Harness Selftest (the coordinator's brief called this last one AC 6).

AC 3 - REAL RUN, GREEN. Credentials came from the workstation .env.credentials (HCLOUD_TOKEN) and the operator key. Fleet box ramped with ops/lxd-fleet/up.sh (12:18Z, 2.29.110.40, ubuntu-26.04). Driven exactly like lxd-fleet.yaml's driver step (marker acquire, then test/install-recovery/lxd/run-forks.sh v2026.10.0-rc.20 --scenario 0-https-only-egress). NO GitHub Actions run URL exists, because it was an operator run. Run identity: marker v2026-10-0-rc-20.manual-faultfleet-485-local-55692, run dir lxd-stage2-v2026.10.0-rc.20-20261013T122652, guest s2-v2026-10-0-rc-20-0-https-only-egress, 12:26:52Z-12:32:33Z. Result: comparison.tsv 'PASS 119s rc=0 installed-v2026.09.3-standalone', STATUS=PASSED. Upgrade v2026.09.3 -> rc.20 reached state=completed in 53s with the data snapshot intact and CA-verified HTTPS 200. docker-proxy loopback health: HTTP 404, meaning the connection was allowed. nft rules listed in the guest are as committed. IPv4 refusal probe passed (curl rc=7). Evidence: test/install-recovery/evidence/STATBUS-357-https-only-nat-1.md (ebb0ee66f).
HONEST LIMITS: (a) the IPv6 probe was VACUOUS, because the LXD bridge has ipv6.address=none. The rule is present in the listing and covered offline only. (b) On LXD the v2026.09.3 install happens when the checkpoint is built, before the policy applies. So this run proves the upgrade and the installed box under HTTPS-only egress, not a from-scratch install under it.

DEFECT FOUND BY THE REAL RUN, FIXED (55731c7cb): the first attempt (harness f0137449d) said PASS but was FALSE-GREEN. lxd_checkpoint_for_scenario only matched the delegation spelling exec "$(dirname "$0")/X.sh". This scenario uses exec bash "$SCENARIO_DIR/0-happy-upgrade.sh", so it forked the candidate's own installed checkpoint and the 'upgrade' was rc.20 -> rc.20 ('already recorded in upgrade table (no change)'). RED before the fix: lxd-checkpoint-identity-test 'FAIL: 0-https-only-egress checkpoint = installed-v2099.01.1-rc.1-standalone'. GREEN after it: 'PASS: 0-https-only-egress resolves its delegate's baseline checkpoint'. The evidence file uses only the post-fix run.

AC 4 (ebb0ee66f): HARNESS_SKIP_DEFAULT removed. Flipped https-only-egress-test.sh (now dies if the marker is present), scenario-selection-test.sh (0-https-only-egress moved to a DEFAULT list that must be selected), and a third pin found in vm-image-selection-test.sh. run.sh --print-selected: before, 28 entries and 0-https-only-egress excluded; after, 29 entries including 0-https-only-egress. RED check: re-adding the marker turns both tests red ('scenario carries HARNESS_SKIP_DEFAULT', '0-https-only-egress is missing from the default install-recovery set').

AC 5 (f0137449d, 99c181e61, 79bf5908c): harness-selftest.yaml runs https-only-egress-test, https-only-egress-mutation-test, scenario-selection-test, vm-image-selection-test and lxd-checkpoint-identity-test. Two CI-only reds were fixed along the way. Run 38396184475 failed with 'HCLOUD_TOKEN not set' (sourcing vm-bootstrap.sh; a dev checkout's .env.credentials had masked it), fixed in 99c181e61 with an offline placeholder. Run 38398317003 failed with 'rg: command not found' in vm-image-selection-test, fixed in 79bf5908c with grep. GREEN at 79bf5908c, job level: Harness Selftest 38398909511 harness-selftest success, all 5 new steps success with PASS lines in the log. Go Test 38398909577 (lint, test) success. app build & lint 38398909682 success. CodeQL 38398908175 (4 analyses) success. Images 38398909474 all builds/manifests/seed success.

OPEN: DoD #2, the scenario running in the default fault set of the NEXT candidate's gate (lxd-fleet.yaml), is not yet observed. Not closed, not Done.
<!-- SECTION:NOTES:END -->
