---
id: STATBUS-453
title: Branch pushes cancel master CI through shared app and Go concurrency groups
status: Done
assignee: []
created_date: '2026-10-06 14:49'
updated_date: '2026-10-07 10:38'
labels:
  - ci
  - release
dependencies: []
references:
  - STATBUS-364
  - STATBUS-452
priority: high
---

## Observed failure

The single master push at 2026-10-06 14:40:41 UTC published `49bb3f1a5817cd25d8986c9da2b581fd83258653`. The app workflow run37480974869/job112328682457 was cancelled during Run App Tests. Its check annotation says: "Canceling since a higher priority waiting request for app-build-lint-master exists".

Competing run37481254979 was a push to `dependabot/npm_and_yarn/app/sharp-0.35.5`, created14:42:43 UTC, SHA `ca5d66a8ca4be7c46f5d4d6620ec398af7e66fd6`. Its later PR run is separate. Remote master remained49bb at14:48, and the coordinator did not push again or cancel any run. Evidence: `tmp/452-ci-app-cancellation-20261006.log`.

The app workflow permits non-ops branch pushes, but its concurrency expression puts EVERY non-PR event into `app-build-lint-master`. The Go workflow has the same expression shape with `go-test-master`, but its push trigger is master-only. Its reachable sibling collision is a manual workflow_dispatch on another branch, not a Dependabot branch push. The observed cancellation was the app run only. Both corrections must preserve their existing trigger filters.

## Small fix and intended behavior

Keep the STATBUS-364 policy: pushes and manual dispatches to master share one group and newer master runs cancel older ones. PR groups remain scoped to their PR ref. Other branch pushes/manual dispatches must have their own ref-scoped groups, never master's group. No trigger filters, release-gate exemptions or cancel-in-progress policy need changing.

Delegate a bounded source change in those two workflows, with one small real-expression behavior check using the existing workflow-test conventions. A check must establish actual group equality/inequality for representative events, not merely forbid a literal token.

## Acceptance Criteria

- [x] #1 Master push and master dispatch group together; PR refs and other branch refs remain distinct, including the observed Dependabot branch. (Verified at source: both workflows carry `(event_name == 'pull_request' || github.ref != 'refs/heads/master') && format('<prefix>-{0}', github.ref) || '<prefix>-master'`, pinned by `cli/cmd/release/workflow_branch_concurrency_test.go`. NOT observed live: every app/go run since the fix has been a `push` to master, so no branch push has exercised the per-ref group in real CI yet. `github.ref` for a PR is `refs/pull/N/merge`, hence distinct per PR.)
- [x] #2 Baseline reproduces the grouping collision; corrected expressions pass behavioral checks and actionlint, preserving newest-master-wins. (Baseline is the real cancellation: master run 37480974869/job112328682457 cancelled by the Dependabot branch push 37481254979 at 14:42:43. `cancel-in-progress: true` retained. actionlint checked by the test itself. Note: the check pins the expression string; it computes no group equality — see the North Star below for why that was accepted rather than papered over with a second model of GitHub's semantics.)
- [x] #3 Independent exact-source review accepts the bounded correction; integrate with patch/source proof and no push during active CI.
- [x] #4 Exact corrected master CI, including app and Go, finishes successfully. Preserve the original cancellation evidence rather than calling it a passing run. (App run37487037267 and Go run37487037416 both concluded success at exactly488f7569; every master push since, through bce5bf39, is green in both. The original cancellation remains recorded as a failure.)

## North Star

**What this is really about.** Master CI is the release gate's evidence: an RC is cut on a commit whose CI is green. A concurrency group is an identity claim — "these runs are the same thing, keep only the newest". `app-build-lint-master` asserted that a Dependabot branch push and a master push were the same thing. They are not, so the bot cancelled the run that was producing the evidence for master, and the tip's green either vanished (Missing) or had to be re-earned. The fix makes the claim true: only a newer *master* push can cancel an in-flight *master* run.

**What it provides.** A green on master means "this exact commit ran its own complete app and Go CI", not "some run eventually won". That is the property the release ladder spends the rest of its machinery protecting; here it cost one expression in two workflows.

**Why this closed without a semantic test.** The remaining AC1 gap is live behaviour, not source correctness: whether GitHub actually keeps master alive under a concurrent branch push. A hand-written evaluator of `&&`/`||`/`format()` would be a second, private copy of GitHub's semantics — it would agree with the expression whenever both share the same mistake, which is precisely the failure it claims to catch. So the choice is the cheap pin plus a live observation at the next real branch push, not a bigger test that cannot do what it claims.

## Closing review, 2026-10-07 10:38 UTC (owner decision A)

Owner reviewed 453 on 2026-10-07. Asked whether strengthening the concurrency check into an event/ref evaluator was worth it, and concluded: no — anything beyond the current pin plus live observation is over-engineering. Closed on that basis. The live branch-push observation (a non-`ops/**` branch push while a master run is in flight, confirming master is not cancelled) is booked as an observation of the next natural occurrence — Dependabot pushes periodically — not as a task and not as a reason to hold the ticket open. `tmp/452-ci-app-cancellation-20261006.log` remains the baseline evidence.

## Reviewed source integration, 2026-10-06 15:00 UTC

Otter froze clean235aab129c92fc923765e1d5c4a611da6173b5e8: two group expressions and comments plus one37-line positive parsed-expression/cancellation contract test. No trigger, exemption, permission or dependency changes. Existing real app cancellation proves the baseline defect. Local RED contract pin and manually transcribed event/ref model are retained separately from actual actionlint; the model does not evaluate GitHub YAML. Focused package tests, build, vet and lint0issues passed.

Independent panda MERGE report tmp/453-concurrency-review.md was read in full. It independently checked both actual workflow sources with actionlint, existing exemption and coverage tests, exact source blobs and unchanged policy boundaries. Hosted corrected CI is explicitly pending, not waived by source MERGE.

The coordinator integrated only this reviewed commit as b8a9d0e33216c8ae3f200026a14352c2e27bd2b6. Stable patch IDs match and the full repository outside backlog notes equals reviewed235aab. Evidence tmp/453-reviewed-integration-20261006.log. No push occurred. Separate Fast Tests on49bb then failed exactly008/016, so the next push waits for their observed, reviewed schema-contract correction as well. Original app cancellation is never counted as green.

## Safety and next action

No production, database, cloud guest, Slack or secret operations. Work in an isolated source worktree, do not push or edit master. At delegation, Fast Tests37481764536 for49bb were still in progress. They subsequently failed exactly008/016 at14:58:22, recorded in STATBUS-452. No next push until their bounded correction is reviewed and ALL existing CI is terminal. STATBUS-451's source-only investigation is complete, implementation remains the following bounded step after these CI corrections.

## Hosted observation started, 2026-10-06 15:26 UTC

The reviewed b8a9 correction is included in pushed488f7569496c0f831d189686be4225e1730df2a0 alongside independently approved008/016 contracts and454 diagnostics. ALL CI was freshly idle15:22:58, then one ordinary push and full remoteSHA verification succeeded. Evidence tmp/452-reviewed-ci-corrections-push-20261006.log. Exact observer186961marz is active, explicit App/Go/Fast conclusions are pending. No second push until every CI run, including dynamic, is terminal. Source MERGE/model/actionlint do not become actual GitHub concurrency behavioral proof merely because the push happened. Original cancelled app evidence and remaining acceptance criteria are preserved.

## Actual hosted checkpoint, 2026-10-06 15:36 UTC

Corrected app run37487037267 and Go run37487037416 have completed successfully at exact488f. Harness37487037415, Images37487037266 and Notify37487037336 are also successful. Exact attributed Fast run37487821209 is still running its fast suite; daemon-floor and livedb steps are pending, not passed. Observer186961marz itself timed out after600s at15:33:45 despite a longer requested deadline. That does not alter any hosted conclusion. Replacement962860c9xw observes the same fullSHA within an explicit540s tool window, with completion wake and the existing15:40:54 fallback. No second source push or RC cut. AC4 remains unchecked until the exact full product CI and actual floor/livedb outcomes are read.

## Final exact hosted conclusion, 2026-10-06 15:48 UTC

Fast37487821209 at488f concluded failure. Actual SQL102 shared plus1 isolated tests passed, and the daemon-floor oracle passed. Livedb failed in eight new recovery-route subcases because their developer-only database prefix refuses the legitimate TestMain-managed statbus_livedb_21294 fixture. A later global SQL diff diagnostic also failed on absent test/regression.out after the Go failure. Full logs/steps retained in tmp/452-ci-488f-{final,failure,full}-20261006.*. Observer962860c9xw exit1 reflects this actual hosted failure, unlike the earlier monitor timeout124. No observer is active; no duplicate observation or push. App/Go source correction remains integrated, but full-CI AC4 is still unchecked and no RC is ready. These narrow test/diagnostic defects are next serial corrections, not a concurrency redesign or excuse to skip livedb.
