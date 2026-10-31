---
id: STATBUS-554
title: >-
  Setup stages are named by slug, run idempotently, and the service account is
  created before the stages that use it
status: In Progress
assignee: []
created_date: '2026-10-31T01:48:00Z'
updated_date: '2026-10-31T11:27:00Z'
labels:
  - setup
  - install
dependencies: []
priority: high
type: bug
ordinal: 477204
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
North Star: setup.sh on a plain Ubuntu box finishes with every check green on its first run; running it again changes nothing; operators name stages by meaning, never by position.

### Zoom out
Stages are identified by number, so moving one changes the meaning of every number after it, and the order cannot be fixed without relabelling. Today ssh-hardening (2) and core-tools (5) act on the statbus account that service-account (7) creates later, so a plain box fails its first run. Uganda and every LXD scenario already had statbus, and the LXD base reruns stages 0 and 2 after a failure, so the gate never saw it.

Design (owner, 2026-10-31):
- Stages have permanent slugs: https-sources, base-system, service-account, ssh-hardening, auto-updates, security-tools, core-tools, user-setup, ci-allowlist. Run order is a list of slugs; service-account runs right after base-system. The screen shows position only for orientation ("Stage 3 of 9: SSH hardening"), computed from the list.
- Every stage is idempotent: a second full run changes nothing and passes its checks. A full run is the default.
- --only-stages <slugs> runs just those (e.g. Uganda: ssh-hardening security-tools). --skip-stages <slugs> stays only for stages this box should not have (security-tools on a private network, https-sources where HTTP is allowed, security-tools on LXD guests). user-setup (cloud only) and ci-allowlist (needs sshdoers settings) keep reporting not applicable on their own. Both options together, an unknown slug, or a number are refused with the list of slugs.
- Dependencies: each stage declares the slugs it requires (ssh-hardening and core-tools require service-account). A stage checks its precondition on the box itself; under --only-stages or --skip-stages, a missing precondition is refused naming the stage to run, never run implicitly.
- All callers and docs switch in the same change: LXD base (lxd-backend.sh, ops/lxd-fleet/base.sh, its retry removed), vm-bootstrap.sh, 0-https-only-egress, test-hardening.yaml (service-account only), DEPLOYMENT, CLOUD, hetzner-bootstrap, setup-ubuntu-lts, host-firewall, comments naming stage numbers (release_sshdoers_drift.go, ops/niue/sshdoers), and the Uganda command in STATBUS-497.

### Zoom in
Plain Hetzner cx33, Ubuntu 26.04 (statbus-manual), setup.sh at c1153315a, non-interactive, SKIP_STAGES=4, 2026-10-31 01:41 UTC: 'populate_authorized_keys: user statbus has no home directory', 'statbus does not exist yet (it is created in a later stage)', summary '2 verification(s) failed: Remote access confirmed before hardening; Docker usable by statbus', exit 1. Reproduced at 9ea14f495 (02:34 UTC). rc.04 smoke 41158823385 shows the same two failures on the LXD base, hidden by its retry.

### Closing review
Documentation: setup-ubuntu-lts.md describes slugs, --only-stages, --skip-stages and dependencies; the stage list comment in the script states why order matters. No memory change.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 A test runs the stages in their order on a box without statbus and every stage passes its checks (red on today's order, green after)
- [ ] #2 A full second run on the same box changes nothing and passes every check (idempotence)
- [ ] #3 --only-stages and --skip-stages take slugs; both together, an unknown slug, or a number are refused naming the valid slugs; a stage whose required stage has not run is refused naming it (tests)
- [ ] #4 Every caller and doc uses slugs; the LXD base runs setup once with no retry, and the Hardening workflow runs service-account by slug; the gate is green
- [ ] #5 On the plain Hetzner box the released setup.sh exits 0 on its first run, and a second run changes nothing (logs recorded)
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Why the gate never caught it: test/install-recovery/lib/lxd-backend.sh runs setup with SKIP_STAGES=4 and, when that exits non-zero, retries with SKIP_STAGES='1 3 4 5 6 7 8' (stages 0 and 2 only), described as a Stage 0 verifier workaround. On a plain base the first run fails here (stage 2, stage 5), stage 7 creates statbus, and the retry then passes stage 2. So every LXD base hides this defect. The fix should also remove that retry so the gate asserts setup succeeds in one run.

2026-10-31 red (before fix, setup script at b24aa359b):
- test/install-recovery/tests/setup-stage-order-test.sh drives main() with stand-in stages on a box without statbus or Docker: 'ssh-hardening ran before statbus existed', 'core-tools ran before statbus existed', order 'https-sources base-system ssh-hardening auto-updates security-tools core-tools user-setup service-account ci-allowlist', exit 1 (tmp/554-red-order.log). Same two failures as the plain Hetzner box.
- test/install-recovery/tests/setup-stage-selection-test.sh: 8/8 FAIL (tmp/554-red-selection.log): --only-stages unknown, --skip-stages security-tools runs it, --skip-stages 4 accepted, refusals do not list stage names.
<!-- SECTION:NOTES:END -->
