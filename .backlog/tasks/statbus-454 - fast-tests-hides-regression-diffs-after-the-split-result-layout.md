---
id: STATBUS-454
title: Fast Tests hides regression diffs after the split result layout
status: In Progress
assignee: []
created_date: '2026-10-06 15:03'
labels:
  - ci
  - testing
dependencies: []
references:
  - STATBUS-452
priority: high
---

## Observed failure

Exact 49bb Fast Tests run 37481764536 failed on 008 and 016, 100/102 tests passed. Its failure diagnostic step ran `cat /statbus/test/regression.diffs 2>/dev/null || true` and printed no diff. The existing helper uses test/regression.out and the expected/results files instead of that assumed diff path. There were no uploaded artifacts to recover. Root retained actual logs in tmp/452-fast-failure-49bb-20261006.log and tmp/452-fast-diffs-49bb-20261006.log. The shared/isolated runner source was inspected, but no live output aggregation producer was reproduced. This required isolated SQL reproduction to obtain the exact diffs.

## Small fix

Use the existing read-only `./dev.sh diff-fail-all pipe` helper in the failure step. It reads the actual combined regression inventory and compares the failed tests' committed expected/result files. Do not invent another result-layout adapter, suppress the original test failure or add a workflow architecture.

## Acceptance Criteria

- [x] #1 Observe the old file-reading payload producing no diff from an offline fixture with failure inventory/result files. The Docker wrapper and live producer are not claimed reproduced.
- [x] #2 Corrected diagnostic invokes the actual unchanged helper and prints both representative failing test diffs. No database access or mutation in this fixture.
- [x] #3 Changed workflow passes actionlint; independent exact-source review and patch/source proof before integration.
- [ ] #4 Next exact-source CI retains its true test conclusion. A future failing run's diff step is useful without making the test pass or replacing actual schema-contract repair.

## Safety

Only fast-tests.yaml's failure diagnostic command and a small existing-pattern offline fixture check may change. No production, database, cloud, credentials, external callback or CI mutation. Separate isolated source worktree, no master/index writes or push. Use captured original failure as baseline evidence and report local fixture limits honestly.

## Implementation checkpoint, 2026-10-06 15:09 UTC

Otter froze one workflow-only commit 5b277d6d4c918e71913c3a3674590c62af091c7d from b8a9d0e33, +1/-2. It replaces the obsolete command with ./dev.sh diff-fail-all pipe and preserves if: failure(), with no new outer error suppression or continue-on-error. Root read the exact delta and own tmp/journal.md, 454-offline-check.sh and 454-prototype.log. Baseline cat payload prints zero bytes. The actual unchanged full dev.sh prints both named expected/changed diffs, exit 0. The fixture prepares an independent git repo, inert seed-cache placeholder and a startup-only sb double rejecting all non-drift invocations. No real DB, Docker, configuration, credentials or live CI result producer is exercised. Actual full actionlint, syntax and diff checks pass. Panda is authorized to independently review this exact pin before integration. Original hosted test conclusion remains failure, corrected hosted acceptance still pending.

## Independent review, 2026-10-06 15:12 UTC

Panda's MERGE at exact 5b277d6d4 was read in full, tmp/454-regression-diffs-review.md. Its own source archive matched every inspected blob and the complete one-file delta. It independently executed the actual unchanged full helper in a safe fixture, observed old payload exit 0/zero bytes and both real diff outputs, checked actual bootstrap trace and unchanged retained-input hashes. Actionlint, syntax, source-boundary checks all exit 0. The original strict migrate-and-test step, failure gating and always-cleanup are byte-identical. This is diagnostic fixture evidence, not live producer or SQL repair proof. At that checkpoint integration/source equality and next real CI remained pending.

## Reviewed integration, 2026-10-06 15:22 UTC

Integrated only 5b277d6d4c918e71913c3a3674590c62af091c7d as 23eaa9af880461696d2f6eae0f6cca3081653b00. Stable patch ID a3abc9c49cade7ca0ffb8b5af1c50c02f3c43f15 matches, the whole workflow equals the reviewed source, and unrelated product source is unchanged. Actual source proof is retained in tmp/452-contract-reviewed-integration-20261006-retry.log. AC #3 is now satisfied. AC #4 still needs the next hosted exact-source conclusion, not an artificial failure injection or a fixture treated as live acceptance.

## Actual producer/step boundary exposed, 2026-10-06 15:48 UTC

Exact488f Fast37487821209 passed SQL102 shared plus1 isolated and daemon-floor, then failed the Go livedb fixture guard. Global if:failure() consequently invokes the SQL diff helper, which fails on missing test/regression.out. The hosted test conclusion remains failure; AC4 is not met. Earlier offline fixture evidence did not reproduce the actual result producer and cannot establish that this global failure diagnostic is correct.

Read-only delegated preparation now maps the actual shared/isolated dev.sh output producers and the workflow's SQL-versus-Go step boundary, with exact file/line evidence in tmp/452-ci-fixture-diagnostics-map.md. Select the smallest producer-grounded correction only after that map. No invented result adapter, masking of the original Go failure, helper rewrite, DB/test operation or implementation is authorized by this preparation. Preserve the current failure and prior reviewed fixture limits.

## Actual producer correction authorized, 2026-10-06 16:22 UTC

The coordinator read the full134-line source/log map and integrated the separately approved managed Go guard. Fresh Snake session_snake_1791303703065_327c830953d1452d, GPT6.1Sol low, now implements only tmp/454-actual-producer-authorization.md in an isolated worktree from72e9f4607fda2a14b1906c5e4716ce0c73f5244e. Allowed tracked paths:dev.sh, fast-tests.yaml, one small offline shell fixture if needed. Persist raw existing pg_regress stdout at both real producers into the existing regression.out, once-fresh parent summary plus child append/standalone reset, unchanged console output and strict command/capture status. Do not clear before test failed reads the prior inventory, erase earlier failures with a later passing child, or invent a TAP adapter.

Restrict diagnostics to the actual SQL-step failure, not later Go/floor failure; say explicitly when pre-pg_regress failure has no readable summary. Repair only existing grep/head no-match handling to let the intended no-failures branch run, treating grep status1 as no match while preserving actual read errors. No continue-on-error or generic error suppression on test execution. Required proof uses actual checked-in command bodies or a prepared/refusing full-entrypoint fixture, not manually typed tee commands; disclose extracted boundaries. No real DB/Docker/network/config/credentials/CI/guest/install/callback or broad suite operations.

Independent Sloth GPT6.1Sol xhigh prepares only scope now, then must receive the coordinator's exact immutable final pin and give full explicit MERGE/BLOCK before integration. Root reports tmp/454-actual-producer-implementation.md and tmp/454-actual-producer-review.md. Previous manual-inventory fixture proof and actual488f failures remain preserved; no hosted acceptance or AC4 credited yet. One reviewed combined push waits fresh ALL-CI idle.

## Frozen actual producer source and review authorization, 2026-10-06 16:29 UTC

Snake froze clean1db224caaf10a2f4bb6e8e946f2f56e258c566e1, exact parent72e9f4607fda2a14b1906c5e4716ce0c73f5244e. Exactly three approved paths:dev.sh+15/-7, fast-tests.yaml+7/-2, one151-line offline fixture, total+173/-9. Root read the complete93-line implementation report, source delta, actual frozen-validation.log and postcommit.log. Bash syntax, focused actual-source fixture, fixture/payload shellcheck, actionlint and diff checks exit0. Global dev.sh shellcheck remains1 due to existing broader warnings, not a global-clean claim; changed-line scope0 preserves intentional existing list expansion SC2086. Original extracted-payload shellcheck1 due to omitted shell specification is retained; corrected -s bash0 adds no product boilerplate.

Observed extracted command boundaries preserve shared7, isolated9, passing child0 and byte-identical console output. Actual extracted parent loop uses its checked-in append assignment, fails9 while retaining failed and passing children. Fresh standalone inventory removes old output; both tee capture failures remain1. First/all no-match reader0, missing inventory1 with SQL guidance, injected grep read error2 remains2. The reader prints both expected/result diffs from the inventory produced by those commands. Baseline observation driver0 is not relabeled RED: it successfully observed missing summary and no-match reader1 before the prototype. Full dev.sh startup/selection/preconditions/flock/runtime Docker or PostgreSQL behavior was not executed or credited.

At16:28:46 the coordinator authorized Sloth's own detached independent review only on exact1db. Explicit full MERGE/BLOCK remained pending at this checkpoint. SQL/floor/livedb execution steps and primary conclusions remain strict; literal workflow missing-summary payload0 is diagnostic-only and cannot convert a failed SQL step to success. Hosted exact-source acceptance and AC4 remained pending.

## Final independent review and integration, 2026-10-06 16:35 UTC

Read the full 101-line Sloth report tmp/454-actual-producer-review.md before integration. Verdict MERGE applies only to exact 1db224caaf10a2f4bb6e8e946f2f56e258c566e1, sole parent 72e9f4607fda2a14b1906c5e4716ce0c73f5244e. The reviewer independently reproduced the parent inverse, mixed and multiple failing producers followed by passing children, prior-failure selection before reset, both capture refusals, actual unreadable/missing input, lookup status 2, literal diagnostic payload and source-body equality. No concrete source blocker. Full parent/final dev.sh ShellCheck each remains 1 for retained existing diagnostics. This is bounded shell-source approval, not a hosted SQL, Go, guest or candidate result.

Integrated only that patch as dc1a8de68d16477a5df3f6fee5477860e8e9f573. Both stable patch IDs are 419b7a42f78b3d206fcc7e9dcede7558758871fd. All three paths and the complete non-backlog source equal the independently reviewed commit. Unrelated source and the dirty STATBUS-448 notes were verified unchanged, the index is empty, and untracked .yarn was preserved. Evidence: tmp/454-reviewed-integration-20261006.log and tmp/454-reviewed-source-proof-20261006.log. No push yet at this checkpoint. Next is one combined reviewed push only after a fresh all-CI-idle check, then the normal exact-source lane. Original hosted failures and all acceptance limits remain retained, AC4 is still pending.

## Hosted checkpoint, 2026-10-06 16:43 UTC

Committed the evidence note as ff31419a87fdc46d1fc8efd555833f2af05ea56d and verified its complete non-backlog tree still matches reviewed 1db. After a fresh paginated all-active-CI query at 16:37:04, one ordinary push and full remote SHA verification succeeded. The initial computed-path safety refusal executed nothing; the justified retry was the sole actual push. Existing 448 changes and .yarn remain untouched.

Observer 662097prn0 ended 1 on a real Harness Selftest failure, not a monitoring deadline. The failure is five log-registration reports in the 451 scenario, not the SQL producer/diagnostic. Complete job/step evidence is retained and a separate bounded 451 follow-up is delegated. At 16:42 the actual App, Go, Images and Notify workflows succeeded, while attributed Fast 37497710543 remains in progress. SQL, floor and managed livedb outcomes and real summary lifecycle are not yet credited. AC4 remains pending, and another source push must wait for every CI run to finish.
