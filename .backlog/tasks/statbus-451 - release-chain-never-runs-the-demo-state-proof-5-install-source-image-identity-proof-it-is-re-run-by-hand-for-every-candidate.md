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

## Observed local progress and next handoff, 2026-10-06 15:37 UTC

The coordinator read Shark's actual tmp prototype and existing driver/checkpoint logs. Baseline resolver selected installed-v2026.09.2-standalone, which is the wrong starting checkpoint for this proof. The real sourceable cloud handler, under controlled refusing transports, refused artifact failure before install, then used pinned version/trust arguments and its actual poststeps. Existing baseline driver/checkpoint logs are old PASS controls, not called RED. Current actual-driver fixtures show two separate rows/logs, both-pass status0, either-route failure and missing-result status1. Current resolver maps both paths to hardened-nothing-installed and the existing historical helper captures09.2/private/prerelease setup. These local fixtures do not run installs or prove a candidate guest result.

Shark remains the sole implementation owner, with final full40 frozen pin, explicit command exits, source/path accounting and provenance/callback controls still required. Independent Sloth session_sloth_1791301012517_d1a6323720dab34f, GPT6.1Sol xhigh, is preparing guides/scope now. Final own detached review and MERGE/BLOCK report tmp/451-independent-review.md require the coordinator's exact frozen authorization, never approval of mutable source. All ACs remain unchecked, no guest dispatch or product442 policy change, and no merge/push while the actual CI/readiness boundary remains unmet.

## Frozen implementation read, 2026-10-06 15:41 UTC

Clean original final source is `7cf241db8dc45ee3f6de47dd45bad12f165501ac`, from exact488f, in the owned451-source worktree. Original commits are bcadcc4ea7008018aa350f95113a74b18f8f7643 and7cf241db8dc45ee3f6de47dd45bad12f165501ac. Coordinator independently read clean status, full commit/scope accounting, diff check, all six full-pin command exits0, combined frozen runner/log and the entire78-line root handoff `tmp/451-implementation-report.md`. Ten paths, +391/-42. Existing LXD child summary gains only15 lines, no new workflow matrix or gate protocol. Main cloud.sh, Go, SQL, product ledger policy and manual runbook are unchanged.

Driver independent route-failure and missing-result controls, actual handler artifact refusal/poststeps, full responding SHA/exact metadata/no-store and both callback routes' positive/missing/old-success controls passed as local fixtures. This is not guest acceptance or proof that a superseded candidate is acceptable. Sloth received the coordinator's exact immutable review authorization at15:38 and is independently reviewing its own detached source. No integration is authorized before its full explicit verdict. The next real named RC must still supply both automatic PASS rows and actual serving/callback/ledger evidence.

## Independent BLOCK and bounded correction, 2026-10-06 15:48 UTC

Coordinator read the complete155-line Sloth report tmp/451-independent-review.md: BLOCK original7cf. The adapter calls actual cmd_install in an OR-list, so Bash disables errexit throughout the production handler. An actual required config/app transport failure47 is swallowed: helper exits0, starts the service and prints install complete. A direct call to the same real handler exits47 and stops. Both reviewer and Shark reproduced this exact difference; original source and logs remain preserved.

Only source-image-proof-helpers.sh and the existing cloud-registry fixture are authorized for the correction. Keep direct bare-handler error semantics, retain output/cleanup with EXIT status preservation, and add the actual failing-poststep control alongside success/artifact-refusal controls. No product cloud.sh, new protocol/gate/matrix, Go/SQL or ledger-policy changes. New clean full40 and coordinator-authorized Sloth re-review must explicitly pass the formerly failing route before integration. Original local PASS checks are not merge approval. All real named-RC ACs remain unchecked.

## Corrected immutable source verified, 2026-10-06 15:56 UTC

Shark froze608e031ce99493951d75b010c9ec8be2164df1af, parent original blocked7cf, with only two authorized paths +35/-6. Coordinator verified clean HEAD/parent, exact scope/diff check, read the whole correction/helper and exact frozen checks runner/log/exit0. Corrected helper and direct handler both exit47 with byte-identical complete failure output, stop before service-start/completion, retain success0 and artifact-refusal1/no transport. Existing cloud/static checks all0. The direct bare invocation preserves real Bash error semantics; the small EXIT cleanup saves original stdout only to avoid writing the captured log back into itself while replaying diagnostics. No product protocol or installer change.

Sloth received corrected immutable authorization15:53:44. Explicit independent report tmp/451-independent-review-608.md remains required before integration. Original tmp/451-independent-review.md and original7cf divergence are preserved. This checkpoint is source/local verification only; all automatic named-RC ACs and owner holds remain unchanged.

## Corrected independent MERGE read, 2026-10-06 16:00 UTC

Coordinator read FULL116-line tmp/451-independent-review-608.md: explicit MERGE exact608e031ce99493951d75b010c9ec8be2164df1af. The reviewer independently replayed its byte-unchanged original probe, observed helper47/direct47 with complete byte-identical output exactly once, no later service-start/completion, success0/refusal1/installer-failure1/wrong-binary1 and owned staging cleanup. Current cloud fixture/static/source checks pass, original BLOCK/probe remain byte-identical, and eight unchanged source blobs retain their original independent review attribution. This is approval of the complete bounded ten-path source range, not permission to skip real gates.

Full78-line corrected implementation handoff was also read at owned451-source/tmp/451-followup/completion-report.md. It supersedes old7cf readiness, retains prototype mistakes and original RED, and reports no source edits after corrected freeze. The initial diagnostic self-append and unavailable local cleanup state were corrected before final source; its generated repeated scratch output was reclaimed after retaining a sample, without altering original independent evidence.

Next integrate ONLY bcadcc4ea7008018aa350f95113a74b18f8f7643,7cf241db8dc45ee3f6de47dd45bad12f165501ac and608e031ce99493951d75b010c9ec8be2164df1af, prove patch IDs/final ten-path equality and unrelated source preservation. No source push until narrow known CI fixture/diagnostic defects are reviewed and ALL CI is freshly idle. All451 ACs still require normal named-RC actual automatic both-cell PASS, with own completed row, serving provenance and local callback evidence. Norway and owner demo remain held.

## Reviewed source integrated, 2026-10-06 16:04 UTC

After notes859daf0e3, all3 approved source commits were cherry-picked conflict-free as59e764cbf0971fbc740dafbacf7017be1136dd77,4cc7c5a27102e2d571d76a0132bd76bfcc024047 and3b63516304817407c5c1638be8c27e7b898162a0. Stable patch IDs respectively cc9d62b85e50e311559dd6338cb7a464c1797d02,181ce07c384d5c8606fdadfc3b7412d46e19f88a andca3cb3bd7ba6dd82bc587f8eac04fda9651d3098 match originals. All10 paths and complete non-backlog source equal the independently reviewed608 tree; changed-path inventory/diff/cached checks pass. Proof tmp/451-reviewed-source-integration-20261006.log and451-reviewed-source-proof-20261006.log. No push or runtime install. Original blocked history and review evidence remain preserved. Actual RC both-cell acceptance still pending, all ACs unchecked.
