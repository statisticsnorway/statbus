---
id: STATBUS-451
title: >-
  release chain never runs the demo-state proof
  (5-install-source-image-identity-proof); it is re-run by hand for every candidate
status: To Do
assignee: []
created_date: '2026-10-05 20:15'
labels:
  - release
  - testing
  - upgrade
dependencies: []
references:
  - STATBUS-436
  - STATBUS-447
  - STATBUS-450
priority: medium
---

## Issue

The owner's objection (2026-10-05): rehearsals run by hand duplicate the release machinery. The scenario `test/install-recovery/scenarios/5-install-source-image-identity-proof.sh` is the only test that starts from a broken box like demo:
- a real v2026.09.2 install
- image tags removed
- the old upgrade service looping on the false "mixed tags" refusal

It then installs the candidate through the official installer, on two paths:
- `CANDIDATE_PATH=scheduled`: `./sb upgrade schedule` + `./sb install` inline dispatch
- `CANDIDATE_PATH=operator`: exactly `./cloud.sh install <box> <tag>`

It carries `HARNESS_SKIP_DEFAULT`, so the LXD fault fleet skips it (`test/install-recovery/lxd/run-forks.sh:103`). The rc.15 fleet (run 37357586680) ran 24 scenarios without it. So for every candidate an agent provisions two Hetzner VMs by hand (`./dev.sh test-install-recovery …` with `INSTALL_TARGET_TAG=<rc>`). Nothing makes that happen, nothing records the result next to the gates, and the release gate does not require it.

Measured cost on rc.15 (2026-10-05):
- scheduled path: 18:27–18:40 UTC (13 min, including VM create/delete)
- operator path: 18:27–18:45 UTC (18 min)

The script's `OLD_LOOP_BUDGET_S=4500` (75 min) is a cap, not the duration. The loop observation exits as soon as the old daemon has refused twice, or after 300 s with no journal output. The cap exists because the old v2026.09.2 daemon processes a discovery backlog at about 12 s per release before it attempts the upgrade. The first version of the proof gave up after 180 s with zero refusals.

Value it delivered on rc.15: the scheduled path showed STATBUS-450 at 18:40, 10 minutes before the arc harness did (18:50). The operator path is the only automated proof of the owner's demo repair command.

## Work

1. Decide placement: a step in the LXD fault fleet (it already provisions candidate-addressed guests on the shared host, and `run-smoke.sh` already exports `INSTALL_TARGET_TAG=$TAG`), or a separate orchestrator job alongside the fleet.
2. Run both `CANDIDATE_PATH` values against the RC tag.
3. Make the result part of the orchestrator's record and the stable gate's required job list (`cli/cmd/release.go`), so a candidate cannot be promoted without it.
4. Remove the manual rehearsal step from the release checklist and the agent runbook once the automated run has passed on one real candidate.

## Acceptance criteria
<!-- AC:BEGIN -->
- [ ] #1 Cutting an RC runs the demo-state proof on both paths automatically, against that RC tag, with no agent action.
- [ ] #2 Its result appears with the other gates (run link and pass/fail), and the stable release gate refuses to promote without a pass.
- [ ] #3 Proven on one real RC: both paths pass in the chain, and no hand-launched rehearsal is needed.
<!-- AC:END -->
