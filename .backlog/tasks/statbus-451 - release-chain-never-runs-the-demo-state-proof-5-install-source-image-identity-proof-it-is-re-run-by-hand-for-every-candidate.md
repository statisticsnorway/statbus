---
id: STATBUS-451
title: >-
  release chain never runs the demo-state proof
  (5-install-source-image-identity-proof); it is re-run by hand for every candidate
status: In Progress
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
- `CANDIDATE_PATH=operator`: currently a copied cloud-install recipe, not literal execution of `./cloud.sh install`. The correction must call the actual sourceable production install handler with isolated harness transport.

It carries `HARNESS_SKIP_DEFAULT`, so the LXD fault fleet skips it (`test/install-recovery/lxd/run-forks.sh:103`). The rc.15 fleet (run 37357586680) ran 24 scenarios without it. So for every candidate an agent provisions two Hetzner VMs by hand (`./dev.sh test-install-recovery …` with `INSTALL_TARGET_TAG=<rc>`). Nothing makes that happen, nothing records the result next to the gates, and the release gate does not require it.

Measured cost on rc.15 (2026-10-05):
- scheduled path: 18:27–18:40 UTC (13 min, including VM create/delete)
- operator path: 18:27–18:45 UTC (18 min)

The script's `OLD_LOOP_BUDGET_S=4500` (75 min) is a cap, not the duration. The loop observation exits as soon as the old daemon has refused twice, or after 300 s with no journal output. The cap exists because the old v2026.09.2 daemon processes a discovery backlog at about 12 s per release before it attempts the upgrade. The first version of the proof gave up after 180 s with zero refusals.

Value it delivered on rc.15: the scheduled path showed STATBUS-450 at 18:40, 10 minutes before the arc harness did (18:50). The operator path is the only automated proof of the owner's demo repair command.

## Work

1. Decide placement: a step in the LXD fault fleet (it already provisions candidate-addressed guests on the shared host, and `run-smoke.sh` already exports `INSTALL_TARGET_TAG=$TAG`), or a separate orchestrator job alongside the fleet.
2. Run both `CANDIDATE_PATH` values against the RC tag.
3. Make both mandatory rows part of the existing full-fleet orchestrator result. The existing stable gate in `cli/cmd/release/release.go` already requires a successful whole-suite run for the exact commit, so reuse that gate rather than adding a new per-route gate list.
4. Remove the manual rehearsal step from the release checklist and the agent runbook once the automated run has passed on one real candidate.

## Acceptance criteria
<!-- AC:BEGIN -->
- [ ] #1 Cutting an RC runs the demo-state proof on both paths automatically, against that RC tag, with no agent action.
- [ ] #2 Its result appears with the other gates (run link and pass/fail), and the stable release gate refuses to promote without a pass.
- [ ] #3 Proven on one real RC: both paths pass in the chain, and no hand-launched rehearsal is needed.
<!-- AC:END -->

## Grounded implementation plan, 2026-10-06 15:26 UTC

Mouse's source-only investigation tmp/451-integration-investigation.md and the coordinator's bounded authorization tmp/451-implementation-authorization.md were read fully. Existing generic checkpoint selection is unsuitable: it selects a prior-release standalone base, while this proof requires actual09.2 private/prerelease. Classify the two wrappers/shared proof as pristine hardened-nothing-installed and use the existing historical installer helper. Export the exact named candidate tag from the current fork driver. Two small default-discovered wrappers select the one scenario body; keep its explicit diagnostic selector excluded to avoid a third run.

The operator proof will call actual cloud.sh cmd_install in an isolated controller subshell with a single harness registry entry and only SSH transport adaptation, using the real candidate artifact verifier/pinned installer during future acceptance. This covers the production install handler, not the outer CLI parser or public HTTP installer download. Scheduled proof keeps real registration/readiness/schedule/official installer inline dispatch. No copied product implementation, registry redesign, fabricated ledger rows or new VM matrix.

Both cells must fetch the artifact-owned full40 SHA through the actual serving proxy/Host and exact release metadata, repeat after scheduler ticks, require their own completed candidate row and capture guest-local callback evidence with positive candidate control. Superseded is not a substitute for completed. No external Slack/webhook and no quiet STATBUS-442 policy repair. Existing comparison rows/log artifacts and stable full-suite exact-commit gate suffice.

Shark session_shark_1791300358117_80eb1d53d2a32a64, GPT6.1Sol low, is assigned ONLY this bounded source implementation from pushed488f7569496c0f831d189686be4225e1730df2a0 in an isolated worktree. No master/index writes, push, DB/cloud/CI dispatch or installs. Observe baseline and tmp prototype before permanent edits, use existing offline driver/checkpoint/handler fixtures, freeze explicit commits for independent exact-pin review. Real images/guests are tested only by the next normal named RC chain. ACs remain unchecked and manual runbook steps remain until both actual automatic paths pass. The historical lost-write/false-completed demo producer is not recreated by this wiring; lower-layer real Go/PG coverage and later official D deployment remain distinct. Early-held convergence must be mapped separately to an existing arc before claiming its guest acceptance. Norway remains held.
