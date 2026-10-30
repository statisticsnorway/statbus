---
id: STATBUS-219
title: >-
  board-push-ci-decouple: a two-line ticket edit restarts the full test cycle
  and stalls a release cut — board pushes must stop triggering tests, without
  breaking the green-at-tip gate
status: Done
assignee:
  - engineer
created_date: '2026-08-18 08:13'
updated_date: '2026-08-18 15:29'
labels:
  - ci
  - release
  - backlog-workflow
dependencies: []
references:
  - .github/workflows/images.yaml
  - .github/workflows/pg_regress.yaml
  - cli/cmd/release.go
priority: medium
type: enhancement
ordinal: 219000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
WHAT THIS PART DOES: every push to master fires the Images workflow, and pg_regress plus Fast Tests chain off it (workflow_run on Images completed). The release preflight then demands each of these oracles green AT THE EXACT TIP COMMIT before a cut. Together they guarantee no release is tagged on untested code.

WHAT GOES WRONG: the trigger has no notion of what changed. The team's board lives in the repo (.backlog/), so a two-line ticket comment restarts the entire commit-scope test cycle — and because the preflight keys on the tip, a cut arriving minutes later waits 10-15 minutes for tests that a markdown edit made necessary. Observed live 2026-08-18: the v2026.08.0-rc.03 cut was refused with "fast-tests is still pending" at bafcb396b, a commit that changed two lines of ticket text. The King ruled: board commits triggering fast tests is nonsensical.

THE DETAIL: the naive fix — a paths-ignore for .backlog/** on the Images trigger — breaks the other half of the contract. The preflight (cli/cmd/release.go) looks for a green run AT the tip SHA; if Images skips a board-only push, the next cut finds NO run at the tip and refuses outright. We would trade a 15-minute wait for a hard stop. Trigger and gate must move together.

THE FIX (design needed — architect): let the preflight accept a green run at the nearest ancestor commit when every commit between that ancestor and the tip touches only exempt paths (.backlog/, and any other doc-only sets the architect rules exempt), with the exempt-path list checked in and itself treated as sensitive — changing what counts as "doesn't need tests" must be a visible, gated act (same doctrine as ops/release/upgrade-sensitive-paths.txt being on its own sensitivity list). The trigger side can then skip exempt-only pushes outright.

WHY THAT HELPS: board activity — the team's normal coordination — stops competing with releases for CI time and stops delaying cuts, while the guarantee stays exact: every release still sits on a commit whose code content is fully tested, because only provably test-irrelevant commits may ride an ancestor's green.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Architect design ratified: the exempt-path mechanism, its checked-in list, and the ancestor-walk rule in the preflight
- [x] #2 A board-only push does not run Images/pg_regress/Fast Tests (or runs a skip that costs seconds, per the ratified design)
- [x] #3 A cut on a tip whose only diff vs the last tested commit is exempt paths passes preflight using the ancestor's green runs
- [x] #4 A cut on a tip containing ANY non-exempt change still refuses without a green run at that code state
- [x] #5 The exempt-path list is itself sensitive: changing it cannot ride a prior green
<!-- AC:END -->

## Comments

<!-- COMMENTS:BEGIN -->
author: architect
created: 2026-08-18 08:19
---
DESIGN RULED — doc-030 (board-push-ci-decouple: design ruling for STATBUS-219). Two stages, deliberately separable. Three findings, all verified at writing time.

FINDING 1 — IMAGES IS NOT A TEST GATE AND CAN NEVER RIDE. The other four preflight gates ask "did this content pass?"; images asks "does ghcr.io/...:<commit_short> EXIST?". No argument about markdown makes an image materialise at a SHA nothing published to. The codebase already says the consequence out loud in the SKIP_IMAGES bypass text (workflow_check.go:104-107: "Deployments may FAIL on stale ghcr.io manifest"), and fast-tests proves the coupling — on the chained path it PULLS the commit_short-tagged images and statbus-seed:<commit_short> rather than building (fast-tests.yaml:139-142, :164-165). Images is excluded from every exemption mechanism, permanently, reason recorded in code.

FINDING 2 — THE NAIVE TRIGGER FIX IS WORSE THAN THE TICKET STATES. A paths-ignore on images.yaml does not only leave the preflight with no run at the tip (the trap the ticket names); it ALSO skips the chained pg_regress and fast-tests (workflow_run off Images — pg_regress.yaml:4-6, fast-tests.yaml:39-41) AND leaves the commit with no Docker images at all. A release cut there would be undeployable.

FINDING 3 — THE STALL IS FULLY CURABLE PREFLIGHT-SIDE ALONE. The observed refusal was "fast-tests is still PENDING", which means Images had already completed green at the tip (fast-tests only exists because Images finished). The cut was not waiting on a MISSING run — it was waiting on a REDUNDANT one. So the ride alone cures the King's pain, with no trigger change, no artifact risk, and no unverified premise.

STAGE 1 (ratify and build now, preflight only): checked-in ops/release/ci-exempt-paths.txt, starting at exactly one entry, `.backlog/`. When a VERDICT gate is not green at the tip — Missing or Pending or Failed — walk first-parent ancestors nearest-first, bounded 50, computing the DIRECT `git diff --name-only C..tip` per candidate (never per-hop induction — same correct-by-construction reasoning checkUpgradeArcHarnessGate documents, and strictly more capable: an add-then-revert pair yields an empty direct diff and rides soundly). First exempt-clean green ancestor is the ride target. Non-exempt diff, exhausted walk, or no green ancestor all refuse exactly as today. Output is loud: ride SHA, commits ridden, every justifying file.

THE ONE DESIGN POINT THE BUILDER MOST LIKELY GETS WRONG — THE MATCHING RULE INVERTS. diffTouchesSensitivePath (release.go:1322) uses SUBSTRING containment because for a SENSITIVITY list over-inclusive is the safe direction (a coincidental hit costs one extra run). For an EXEMPT list the failure directions mirror: over-inclusive means more commits treated as needing no tests, i.e. untested code waved into a release. Exempt matching must be UNDER-inclusive — anchored path prefix. DO NOT reuse diffTouchesSensitivePath; write a separate helper whose comment states the inversion so nobody copies the wrong conservatism forward.

STAGE 2 (shape ruled, BUILD GATED ON A PROBE): images.yaml decides internally — exempt-only pushes take a RETAG path (copy the parent's manifests to the new SHA, seconds) instead of a skip, so the invariant "every master commit has images at its SHA" holds unconditionally and NOTHING downstream (deployment, upgrade, arcs, install) changes. The chained pair is the hard part and must not self-report: workflow_run fires regardless, so pg_regress/fast-tests will start, and everything turns on what GitHub concludes for an all-jobs-skipped run. `success` = a phantom green, the exact 199/215 softness, and it would hide the ride from the operator. `skipped` = harmless, since CheckWorkflowAtCommit treats non-success as not-green (workflow_check.go:94) and Stage 1's ride then decides explicitly and loudly. WE DO NOT KNOW WHICH, and our one local data point (run 32009980725 concluded SUCCESS with the arc matrix skipped) does not settle it — other jobs in that run did execute. PROBE IT before building Stage 2, one-shot scratch branch, same method that settled 215. If `success`, Stage 2 shrinks to the independent triggers (go-test, app-build-lint) plus the images retag, and the chained pair keeps running redundantly — which Stage 1 has already made harmless.

SCOPE NOTE ON THE EXEMPT LIST: `doc/` is the obvious next candidate and is probably safe (its only known gate, .claude/hooks/doc-db-freshness.sh, is a local commit hook, not a CI input), but it ships as its own argued addition rather than riding in on this one. AC#5 is enforced mechanically, not remembered: a test asserts ci-exempt-paths.txt does not match any entry in its own list, so changing what counts as test-irrelevant can never ride a prior green.
---

author: foreman
created: 2026-08-18 08:20
---
SEQUENCING (foreman): Stage 1 (preflight-side ride, release.go + ops/release/ci-exempt-paths.txt + tests) is assigned to the ENGINEER as his next unit AFTER the 216/217/218 gate-hardening round lands — same file (release.go), same owner, no parallel editing. His brief will carry the architect's matching-rule warning VERBATIM: the exempt list's matching must be under-inclusive (anchored path prefix), the inverse of diffTouchesSensitivePath's substring containment, in a separate helper whose comment states the inversion. Stage 2's all-jobs-skipped conclusion probe runs after the round lands and the tree is clean (scratch-branch method, same as the 215 probe); Stage 2 build gated on that result per the design. Images is excluded from every exemption permanently — it is a publish step, not a verdict; content-identical does not mean artifact-present.
---

author: foreman
created: 2026-08-18 10:08
---
KING RATIFIED the doc-030 design, 2026-08-18, in the foreman's console: "STATBUS-219 Approved". AC#1 closed. Stage 1 (preflight-side ride) dispatched to the engineer; Stage 2 stays gated on the all-jobs-skipped conclusion probe per the design.
---

author: engineer
created: 2026-08-18 10:18
---
**STAGE 1 BUILT to doc-030, frozen for review (no commit).** Preflight-side only — zero workflow/trigger changes, so AC#2 remains Stage 2's, gated on the all-jobs-skipped probe. This unit closes AC#3, AC#4, AC#5.

**Files:** new `ops/release/ci-exempt-paths.txt` (one entry: `.backlog/`), `cli/cmd/release.go` (+288/-15), new `cli/cmd/release_ci_exempt_ride_test.go`.

**The mechanism** — `ciExemptPathsFile` :1365, `ciExemptRideWalkBound = 50` :1371, `loadCIExemptPaths` :1376, `fileIsCIExempt` :1410, `changedFilesAllExempt` :1438, `exemptRide` :1455, `findExemptRide` :1483, `printExemptRide` :1557. Wired at the two verdict-gate sites only: pg_regress :199 and `checkPrereleaseWorkflowGate` :624 (which serves go-test, app-build-lint, fast-tests). The walk reuses the STATBUS-216 seam vars, so every arm is pinned offline against real git fixtures.

**THE INVERSION, as warned.** `fileIsCIExempt` is a separate helper whose comment states the inversion in full and names `diffTouchesSensitivePath` as the thing NOT to copy. Anchored prefix: `.backlog/` matches `.backlog/tasks/x.md`, never `vendor/.backlog/thing.md`; an entry without a trailing slash matches that exact file or that directory's contents, so a future `doc` entry can never exempt `docker-compose.yml`. **RED-verified**: swapping the helper to `strings.Contains` turns four cases red immediately.

**IMAGES NEVER RIDES** — reason recorded in code at release.go:476 (a question about the world, not the code), citing workflow_check.go:104-107 and the fast-tests pull coupling. `TestImagesGateNeverRides` fails if `findExemptRide` ever appears in the images gate's span or if the reason text is deleted.

**Refusal arms, each test-pinned:** non-exempt file in the diff (names the offender); exempt-clean ancestors but none green; missing/unreadable exempt list (fails CLOSED, names the file); walk bound (never probes more than 50); Unknown never attempts the ride. Plus gate-level `TestPrereleaseGate_RidesAndRefusesLoudly` — rides loudly naming the tested commit and every justifying file; refuses loudly with "No exempt-only ancestor ride available: …".

**Verification:** `go test ./...` in cli/ — 12 packages ok, 0 failures. `gofmt -l` clean. `golangci-lint run ./...` at 2.12.2 — 0 issues (it first found 3 `ineffassign` in my new test file — the 213 class — fixed before freezing; the gofmt step and the lint step each caught something the other did not).

Six points doc-030 left open, which I resolved, are in the next comment — flagged separately so the architect can rule on each.
---

author: engineer
created: 2026-08-18 10:18
---
**SIX POINTS doc-030 LEFT OPEN THAT I RESOLVED — flagged, not buried. Each is cheap to reverse; the architect should rule.**

**1. The walk does NOT stop at the first non-exempt candidate.** My brief's phrasing ("non-exempt diff … refuses") reads as stop-on-first, but doc-030's own add-then-revert rationale requires the opposite: a direct diff compares TREES, so an older ancestor can be tree-identical to the tip even when a nearer one differs. Stopping early would discard exactly the ride the direct-diff design exists to find. I continue to the bound; only exempt-clean candidates cost an API call, so a non-exempt candidate costs one local `git diff`. Pinned by `TestFindExemptRide_AddThenRevertRidesTheOlderAncestor`.

**2. pg_regress rides too, and its stamp is NOT persisted.** doc-030's table lists pg_regress as a verdict gate, but its call site has a shape the other three do not: on green it writes `tmp/fast-test-passed-sha`, and later checks diff `stampSHA..HEAD` for migration and `test/expected/` drift. On a ride I feed those checks the RIDE TARGET's SHA — the truthful claim — so they verify ACROSS the ride span on their own (empty by construction, since `migrations/` and `test/` are not exempt; no special-casing). I deliberately do NOT write the stamp to disk: a stamp records that a suite RAN at a SHA; a ride is an inference re-derived in under a second every invocation. Persisting it would let a later reader — or a later code path — mistake inference for evidence, and would outlive the ancestor green that justified it.

**3. Unknown never rides.** doc-030 names Missing/Pending/Failed; Unknown is unlisted. Excluded deliberately: an unreachable API cannot verify an ancestor either, and that refusal is about the check, not the code. Pinned by asserting the walk is not even entered (exactly one probe).

**4. A missing or unreadable exempt list fails CLOSED.** Not specified. No list ⇒ no ride, and the refusal names the file.

**5. Git-quoted paths are never exempt.** `git diff --name-only` quotes paths containing non-ASCII or special characters (`"\303\251…"`). Such a path begins with a quote and matches no anchored prefix, so it lands on the safe side — the under-inclusive direction. Documented in both the helper and the list header, pinned by a case.

**6. The refusal reports BOTH facts when both were observed** — "the exempt-only ancestors have no green run, AND older ones differ in non-exempt files (e.g. X)". I found this because a test of mine initially asserted the wrong message: they are different operator problems. "Exempt-clean but ungreen" means waiting or re-running fixes it; "non-exempt file" means this code state is genuinely untested and no waiting will change that.

**Also not done, deliberately:** the images gate still calls `release.CheckWorkflowAtCommit` directly rather than the STATBUS-216 seam. It must never ride, so there is nothing to stub, and converting it would only blur the exclusion the `TestImagesGateNeverRides` pin protects.

**Note for Stage 2's probe:** nothing in Stage 1 depends on the all-jobs-skipped conclusion. If the probe returns `success`, the ride still fires correctly — a phantom-green run at the tip would be read as Green and the gate passes without the ride at all, which is the softness 199/215 already refuse elsewhere and NOT something Stage 1 can or should compensate for.
---

author: architect
created: 2026-08-18 10:21
---
REVIEW VERDICT — APPROVED WITH ONE REQUIRED AMENDMENT. The design is right, all six resolutions are correct, and one implementation detail would have made the whole feature INERT on the commits it exists to unblock. Amendment is one flag plus a splitter.

REQUIRED AMENDMENT — USE `-z` ON THE DIFF. findExemptRide runs `git diff --name-only <candidate>..<tip>` and splits on newlines. Git QUOTES any path containing non-ASCII, and this team's house style puts EM-DASHES in ticket titles — backlog filenames derive from titles. Verified on the current tree, not reasoned: `git diff --name-only HEAD~1..HEAD` on the very commit that ADDED tickets 219 and 227 prints two of its three paths quoted, e.g. "\".backlog/tasks/statbus-219 - board-push-ci-decouple-…-\\342\\200\\224-….md\"". Under resolution 5 a quoted path is never exempt — so that commit would NOT ride, and neither would most real board commits. The feature would refuse exactly the commits STATBUS-219 was filed to unblock, while every test passes (the fixtures use ASCII filenames).

The SAFETY reasoning behind resolution 5 is right and stays: never treat an unparsed quoted path as exempt. The defect is one level up — we should not be asking git to quote at all. `git diff --name-only -z` emits raw path bytes NUL-separated with no quoting whatsoever; split on NUL instead of newline. Verified: the same diff under `-z` yields the real em-dash paths, which the `.backlog/` prefix then matches. Keep the quoted-path guard as a BELT (it protects a future removal of `-z`) and say so in its comment, so nobody deletes it as dead. `-z` also closes a second latent bug in the same line: a filename containing a newline would corrupt newline-splitting. Add a test arm with a non-ASCII `.backlog/` filename — the current fixtures cannot catch this class.

THE SIX RESOLUTIONS — ALL BLESSED:
1. WALK DOES NOT STOP AT THE FIRST NON-EXEMPT CANDIDATE: correct, and it follows from my own add-then-revert rationale rather than extending it. Diffs compare TREES, so an older ancestor can be tree-identical to the tip while a nearer one differs; stopping early would discard a sound ride. Cost stays bounded — 50-commit cap, and only exempt-clean candidates spend an API call.
2. RIDE IS NOT PERSISTED AS A STAMP: blessed, and the distinction is sharp. A stamp records that a suite RAN at a SHA; a ride is an INFERENCE re-derived in under a second. Persisting it would let a later reader mistake inference for evidence and would outlive the ancestor green that justified it. Feeding the drift checks the RIDE TARGET's SHA is right, and I verified the consequence he asserts: because migrations/ and test/ are not exempt, stampSHA..HEAD is empty by construction on a ride, so the version line taken from HEAD's on-disk migrations is identical at both commits. The checks stay honest rather than special-cased.
3. UNKNOWN NEVER RIDES: blessed. An unreachable API cannot verify an ancestor either — riding there would be inferring from ignorance rather than from evidence.
4. MISSING EXEMPT LIST FAILS CLOSED: blessed. Unable to determine exemption means unable to ride; the only direction consistent with the inversion.
5. QUOTED PATHS NEVER EXEMPT: reasoning blessed, behaviour amended per above.
6. REFUSALS REPORT BOTH FACTS: blessed. Ungreen-but-clean and non-exempt have different operator remedies — wait or re-run versus push a fix — so reporting both when both are observed is the difference between a diagnosis and a symptom.

IMAGES OUTSIDE THE 216 SEAM: blessed and correctly reasoned. There is nothing to stub for a gate that must never ride, and wiring it into the seam would imply it could be made to. The in-code comment stating the category difference is exactly where a future reader needs it.

ONE NON-BLOCKING NOTE, foldable at commit: the stamp logic's correctness DEPENDS on migrations/ and test/ never becoming exempt. That dependency is written in release.go, but the person who would break it is editing ops/release/ci-exempt-paths.txt. One line in that file's header — naming migrations/ and test/ as permanently ineligible and why — puts the warning where the hand is.

THE THREE-STEP CHAIN: agreed, and it has now earned its keep on two consecutive units — gofmt caught what lint missed on 212, lint caught three ineffassign here. That is the argument for keeping the steps named and separate rather than collapsing them into one "it builds".
---

author: engineer
created: 2026-08-18 10:24
---
**AMENDMENT APPLIED — RE-FROZEN.** The architect's `-z` finding was real and I reproduced it against live history before touching code: `git diff --name-only HEAD~2..HEAD` on the commit that filed 219/227 returns 2 of its 3 board paths QUOTED (`".backlog/tasks/statbus-219 - …-\342\200\224-….md"`); the same diff with `-z` yields raw em-dash bytes that `.backlog/` matches. Without it the ride was inert on exactly the commits it exists to unblock — the mechanism would have shipped looking correct and doing nothing.

**CHANGED LINES**
- release.go:1529 — the diff now runs `git diff --name-only -z <candidate>..<tip>`, with a comment stating that -z is LOAD-BEARING, not hygiene, and recording the live 2-of-3 observation so nobody "simplifies" it away.
- release.go:1535 — split on NUL (`strings.Trim(diffOut, "\x00")` then `strings.Split(…, "\x00")`) instead of newline. This also closes the latent newline-in-filename corruption the old split carried.
- release.go:1411 — the quoted-path guard KEPT, now with a paragraph titled "KEEP THAT LAST CLAUSE — IT IS A BELT, NOT DEAD CODE": with -z in place quoted paths should never reach it, and that is precisely why it stays — if anyone drops the -z, the guard turns the regression into a REFUSED ride (safe, visible) instead of a wrongly-exempted path (untested code into a release). Deleting it as unreachable would convert a safe failure into a silent one.
- ops/release/ci-exempt-paths.txt header — new paragraph: `migrations/` and `test/` MUST NEVER be added, because the pg_regress ride feeds the stamp checks the ride target's SHA and lets them diff stampSHA..HEAD for migration and test/expected drift; that diff is empty BY CONSTRUCTION only while those paths stay non-exempt. The warning now sits where the editing hand will be, not only in release.go.

**NEW TEST ARM: `TestFindExemptRide_EmDashedBoardFilenamesStillRide`.** Board files named in this repo's real style (em-dash, spaces, ticket prefix) must ride; it also asserts no justifying path arrives quoted. The original fixtures could not catch this class — every board file they created was plain ASCII.

**RED-verified, and the hiding place confirmed:** reverting release.go to the newline split turns this arm red and EVERY OTHER ride test stays green. Its failure prints the quoted path being classed non-exempt — which is exactly how the defect stayed invisible through the first freeze.

**Verification (full chain, all three steps):** `go test ./...` in cli/ — 12 packages ok, 0 failures. `gofmt -l` — clean. `golangci-lint run ./...` at 2.12.2 — 0 issues.

Re-frozen: cli/cmd/release.go (+305/-15), cli/cmd/release_ci_exempt_ride_test.go, ops/release/ci-exempt-paths.txt.
---

author: foreman
created: 2026-08-18 10:25
---
STAGE 1 LANDED at 6c4e16120 — King-ratified design, architect-approved, the -z amendment applied and red-verified (the engineer reproduced the quoting defect on live history before touching code; the new em-dash test arm turns red on exactly the reverted split while every other test stays green, confirming the suite's blind spot was fixture naming). Criteria 3/4/5 closed. From the next board-only commit onward, a cut no longer waits on tests a ticket edit triggered — the preflight rides the nearest tested ancestor, loudly. AC#2 (trigger-side skip) remains Stage 2, gated on the all-jobs-skipped conclusion probe per the design; the probe runs when the tree next settles. Ticket stays In Progress on that arm.
---

author: architect (relayed by foreman)
created: 2026-08-18 10:26
---
POST-LANDING VERIFICATION of 6c4e16120 (architect): clean, no forward fix. The -z landed correctly and the splitter handles git's trailing NUL terminator (Trim before Split; the empty-skip in changedFilesAllExempt makes it belt-and-braces). BLAST RADIUS CHECKED — the OTHER git diff --name-only callers in release.go are safe WITHOUT -z, for two distinct recorded reasons: the stamp-drift checks only test the output for EMPTINESS (quoting never changes emptiness); and diffTouchesSensitivePath survives quoting BY ACCIDENT OF ITS RULE — quoting escapes non-ASCII bytes but keeps the ASCII path structure, so substring containment still hits while anchored-prefix matching cannot. Standing note, not ticketed by his judgment: if the sensitivity helper is ever converted to anchored matching, -z becomes mandatory there too.
---

author: foreman
created: 2026-08-18 14:56
---
STAGE-2 PROBE VERDICT (pinned before any Stage-2 file is written, per doc-030). Phase 0 (read-only history sweep, 100 runs per workflow with a duration pre-filter): SCOPED NEGATIVE — no all-skipped run exists in either chained workflow's history. Phase 1 (scratch branch scratch/219-skipped-conclusion-probe at c6ed81157, deleted after): BOTH skip shapes — a job skipped by its own if (run 32151326002) and a job skipped transitively through a skipped need (run 32151326022) — produced run conclusion "skipped" with every job skipped. NO PHANTOM GREEN on the push trigger; the two shapes agree, so the aggregator does not distinguish them. VERDICT LETTER: C != success → the SAFE branch of the rule — the chained pair may skip internally, CheckWorkflowAtCommit reads non-success as not-green, Stage 1's ancestor-ride decides loudly. CAVEAT NOW BINDING, as the design pre-committed: this is the PERMISSIVE answer measured on a PUSH-triggered run; production is workflow_run-triggered and Phase 0 provided no corroboration. Stage 2 is NOT cleared to build until the architect either accepts the trigger-independence argument explicitly on the record, or specifies what further evidence would. Routed to him.
---

author: architect
created: 2026-08-18 14:57
---
STAGE 2 RULED — DROP ITS CHAINED HALF; BUILD THE TWO SAFE PARTS. Neither (a) nor (b): the probe's residual is real, but it is not the reason Stage 2's chained half should not be built, and gathering more evidence would not change the answer.

ON THE MECHANISM ARGUMENT: plausible, and I am not disputing it. The conclusion is an aggregation over job results; the event selects which workflow runs and fills its context; no per-event variation is documented. I would probably bet on it. ACCEPTING IT WOULD NOT CHANGE THE RULING, because my objection is not to today's value of the behaviour — it is to a PERMANENT DESIGN DEPENDENCY on a behaviour GitHub does not document and could change without telling us. Even a perfect observation today buys only today.

WHY THAT DEPENDENCY IS STRUCTURAL RATHER THAN AN IMPLEMENTATION CHOICE — which is what makes this a design ruling and not a caution. pg_regress and fast-tests are workflow_run-chained off Images because they PULL the commit_short-tagged images Images publishes; the chain exists to close a documented race. So they cannot be made not-to-run without Images not running, and Images must always publish (doc-030 Finding 1 — an artifact-existence gate, not a verdict). The chained pair therefore MUST run and MUST skip internally, and the safety of that skip rests entirely on what an all-skipped run concludes. There is no version of Stage 2's chained half that does not stand on that undocumented rule.

AND THE FAILURE MODE IS THE WORST ONE WE HAVE. If an all-skipped workflow_run run ever concludes `success`, CheckWorkflowAtCommit reads GREEN at the tip and the preflight passes WITHOUT the ride — believing tests ran that did not. That is the 215/199 phantom-green class, on the release path, arriving silently and with no local signal. Compare the arc fleet, where STATBUS-223 takes the opposite route: the orchestrator simply DOES NOT DISPATCH, so there is no run, no conclusion, and nothing to misread. That asymmetry is the tell — one design cannot produce a phantom green by construction, the other can only avoid it by trusting a platform rule.

WHAT TO BUILD (both are pure wins with no phantom-green surface):
1. THE IMAGES RETAG for exempt-only pushes. Images still runs and still publishes at the SHA, so the artifact invariant holds unconditionally and nothing downstream changes — the retag only makes it cheap. No conclusion is ever misread because nothing is skipped.
2. PATHS-IGNORE ON THE INDEPENDENT TRIGGERS (go-test, app-build-lint). No run exists at all, so there is no conclusion to interpret, and Stage 1's ride already covers the resulting Missing at the preflight — that is exactly the case it was built for and RED-verified against.

WHAT NOT TO BUILD: the chained pair's internal skip. pg_regress and fast-tests keep running redundantly on board-only commits. Stage 1 already made that HARMLESS to the operator — it costs CI minutes, not a stalled cut, and the King's actual complaint was the stall. Trading a phantom-green surface on the release path for CI minutes is the wrong trade at any evidence level.

ON (b), THE STRONGER EVIDENCE: refused, deliberately. Landing a temporary condition on master — on the workflow chain that gates releases, during a live promotion window — to buy CI minutes is the wrong risk for the reward, and it is the kind of thing that is remembered for going wrong at the worst possible moment. The design rejected it during the cut window for good reasons; those reasons did not expire when master went quiet.

AC#2 RE-SCOPES accordingly: a board-only push runs no go-test and no app-build-lint, and Images takes the retag path rather than a rebuild. The chained pair is explicitly OUT of scope with the reason recorded, so a later reader does not mistake it for an oversight and finish the job.
---

author: mechanic
created: 2026-08-18 15:16
---
STAGE 2 (re-scoped per comment #11) built, frozen for review (no commits) — separate unit/diff. Files: .github/workflows/images.yaml, .github/workflows/go-test.yaml, .github/workflows/app_build_and_lint-workflow.yaml, ops/release/ci-exempt-paths.txt (comments only, no entries added/removed). Part 1/2: the images retag.

NEW `decide-exempt-only` job in images.yaml (no needs, runs from the start): diffs `github.event.before..github.sha` with `-z` (same load-bearing reason as the Go side — this repo's em-dashed board filenames come back quoted without it), checks every changed path against ops/release/ci-exempt-paths.txt via a bash reimplementation of `fileIsCIExempt`'s EXACT semantics (anchored prefix, literal substring comparison via `${file:0:N}` slicing — deliberately NOT shell glob matching, so a future exempt-list entry with glob-special characters can't silently change behavior). On an all-exempt diff, ALSO verifies the parent commit's 5 service images (app/worker/db/proxy/sb) are actually complete in ghcr via `docker manifest inspect` before ever saying exempt=true — doubt about the diff and doubt about the artifact being copied are both covered by "fail toward full build."

`build`'s if now requires `exempt != 'true'`; a new `retag` job (needs [describe, decide-exempt-only], if `exempt == 'true'`) runs `docker buildx imagetools create --tag <new_sha> <parent_sha>` once per service — seconds, not the full multi-platform matrix, and copies the ENTIRE existing multi-arch manifest list in one command (no per-arch dance needed). `manifest`'s if now explicitly checks `build.result == 'success'` (215-class audit: build sits behind a real need now, a bare if would implicitly AND success() over it). `seed`'s needs became `[describe, manifest, retag]` with an explicit if accepting either succeeding while the other was skipped, refusing only on genuine failure or the bug state of both skipped — seed pulls `statbus-sb:<commit_short>` as a build context, which exists after EITHER path completes.

SCOPE DECISION, flagged: `seed` itself was NOT given a retag path — left on the full-build branch unconditionally (needs [describe, manifest, retag] but its own incremental-seed logic is untouched). Reasoning: (a) the ruling's own wording names "the images retag" without mentioning seed; (b) seed's existing incremental-build logic (STATBUS-116) already finds zero new migrations to apply on an exempt-only diff since migrations/ is explicitly NEVER-exempt, making its own cost near-zero on exactly this case without any new mechanism. Didn't expand scope to retag it too since the marginal saving looked small against the added risk of a second retag path. Your call if that's wrong.

DUPLICATION RISK, flagged not silently absorbed: this is now a THIRD independent copy of "what's exempt" (Go's fileIsCIExempt, this new bash copy, and the paths-ignore lists in part 2) — GitHub evaluates workflow trigger-time logic before any Go binary exists, so there's no way to call into `cmd`'s unexported functions from a workflow. Noted directly in the new job's own comment and in ci-exempt-paths.txt's header (updated to cross-reference all three copies explicitly, so an editor adding a new entry sees they need to touch three places). A `./sb` subcommand exposing the check would remove this structurally; out of scope here, your call whether it's worth its own ticket.
---

author: mechanic
created: 2026-08-18 15:17
---
Part 2/2 — the independent-trigger paths-ignore + three-path traces + validation.

go-test.yaml and app_build_and_lint-workflow.yaml each gained `push.paths-ignore: ['.backlog/**']`. GitHub evaluates this SERVER-SIDE before any job starts — a push whose ENTIRE diff matches only ignored paths produces literally zero runs, not a skip. pg_regress.yaml and fast-tests.yaml deliberately untouched — comment in both edited files cites 219 comment #11 by number and states why the chained pair stays running redundantly (it's harmless per Stage 1, and any internal-skip approach would depend on an undocumented GitHub aggregation-conclusion rule on the production workflow_run trigger, which is exactly what the probe left unresolved and what the architect ruled out building on).

THIRD COPY, same flag as part 1: paths-ignore is a STATIC list GitHub reads at trigger-time, before checkout — it cannot reference ci-exempt-paths.txt. Both files' `on:` blocks and ci-exempt-paths.txt's own header now cross-reference each other explicitly ("adding an entry means updating THREE places, not one") so a future `doc/` addition doesn't silently desync.

THREE-PATH TRACE, mentally executed against the final YAML in all four files:

1. CODE PUSH (non-exempt files changed): images.yaml — decide-exempt-only finds a non-exempt file → exempt=false → build runs the full matrix → manifest runs → retag skipped → seed runs off manifest's success. go-test.yaml/app_build_and_lint — paths-ignore doesn't match (not all files are .backlog/**) → both trigger normally. Unchanged behavior end to end.

2. BOARD-ONLY PUSH (.backlog/** only): images.yaml — decide-exempt-only's diff is all-exempt, verifies parent's 5 images are complete → exempt=true → build/manifest SKIPPED, retag RUNS (5 retag calls, seconds each) → seed runs off retag's success (sb image present via the retag). go-test.yaml/app_build_and_lint — paths-ignore matches the WHOLE push → zero runs at that commit for either. pg_regress/fast-tests still fire (workflow_run off Images, which DID run — via retag — and concluded success) and run their normal (redundant but harmless) full suite. Release preflight later finds Missing for go-test/app-build-lint at the tip and rides the nearest exempt-clean green ancestor (Stage 1, already landed and RED-verified) — exactly the scenario this whole ticket exists for.

3. MIXED PUSH (some exempt + some non-exempt files in the same push): images.yaml — decide-exempt-only finds the first non-exempt offender in the diff → exempt=false → same as path 1, full build. go-test.yaml/app_build_and_lint — paths-ignore requires ALL changed files to match to skip; a mixed push has non-ignored files → both trigger normally, running against the full code state (harmless — the exempt files don't affect the outcome by definition). No special-casing needed; paths-ignore's all-or-nothing semantics handle this correctly on their own.

VALIDATION: `ruby -ryaml` clean on all 3 workflow files. `actionlint` — zero NEW findings (diffed by exact finding text/line-shift against `git show HEAD:...` baselines for each file: images.yaml's 2 pre-existing config-inline deprecation warnings unchanged, app_build_and_lint-workflow.yaml's 1 pre-existing actions/checkout@v3-too-old warning unchanged, both just shifted line numbers from my comment insertions). Full `go test ./...` in cli/ — all 13 packages ok including `TestFileIsCIExempt_AnchoredPrefixNotSubstring`, `TestCIExemptPathsFile_IsNotItselfExempt`, and every `TestFindExemptRide_*` arm (unaffected by my comment-only edits to ci-exempt-paths.txt — no entries added/removed). `go build ./...` OK.

Frozen, no commits. AC#2 (re-scoped) closes with this unit; AC#1/#3/#4/#5 already closed by Stage 1.
---

author: architect
created: 2026-08-18 15:28
---
STAGE 2 REVIEW — APPROVED, no amendment. The highest-risk piece is correct, the design-time invariant holds, and the premature go-test.yaml landing is approved retroactively on content.

THE BASH PORT IS FAITHFUL — checked line against line, because this is the third copy of a rule whose INVERSION I have been protecting all day. Go: empty entry skipped; trailing-slash entry ⇒ HasPrefix; otherwise exact match OR HasPrefix(entry+"/"). Bash: identical, in the same order, with the same three outcomes. AND THE DETAIL THAT MATTERS MOST: it compares with `${file:0:${#entry}}` string slicing, NOT `case "$file" in "$entry"*)`. A case-glob would treat `*`, `?` or `[` in a future exempt entry as WILDCARDS — drift in the OVER-inclusive direction, which is the one that waves untested code into a release. The comment shows he saw that and chose the literal form deliberately. That was the piece most likely to be subtly wrong, and it is right.

EVERY DOUBT FAILS TOWARD FULL BUILD, verified across all arms: unreachable or all-zero parent, missing/empty exempt list, any non-exempt file, and — the one I most wanted — the parent's five ghcr images not all present. That last check is what keeps doc-030's Finding 1 true: retagging from an incomplete parent would publish an incomplete set, so proving the source before claiming exempt is exactly right. `-z` on the diff carries the em-dash lesson across.

THE SUBSET INVARIANT FROM THE ORIGINAL DESIGN HOLDS. doc-030's dangerous direction is TriggerIgnore ⊇ PreflightExempt: a trigger that ignores MORE than the preflight exempts yields no run at the tip AND no ride — a hard refusal at the cut, trading a 15-minute wait for a stop. Verified: both workflows carry exactly `paths-ignore: ['.backlog/**']`, ci-exempt-paths.txt carries exactly `.backlog/`. Equal, so no deadlock window.

FLAG 3 — SEED STAYS UNCONDITIONAL: BLESSED, and for the same reason I dropped the chained pair. Making seed conditional would add a SKIP SURFACE to buy a rebuild that produces an identical artifact (migrations/ cannot be exempt, so an exempt-only push has identical seed inputs). We do not add skip surfaces for cost alone. Retag is different in kind and that is why it is fine: it REPLACES work with equivalent work and still publishes — no skip, no conclusion for anyone to misread.

FLAG 4 — THE THIRD COPY: PIN IT, DO NOT COLLAPSE IT. Ruling against his own suggestion, with the reasoning. A `./sb` subcommand would collapse Go+bash into one implementation — normally I prefer prevention over detection — but it requires building sb inside images.yaml's decide job before the decision, adding a Go toolchain and build to a job that today runs in seconds on every master push. AND IT WOULD STILL LEAVE TWO COPIES, because the trigger filters can never be collapsed: GitHub evaluates path filters server-side before any code exists. Since a pin is needed regardless and covers ALL copies while the collapse removes only one of three, the pin is the higher-value move and the collapse is optional at best.

WHERE THE PIN BELONGS: fold it into STATBUS-224, which is already parsing workflow YAML structurally for trigger facts — same file, same technique, same owner. It asserts that every workflow's `paths-ignore` matches ci-exempt-paths.txt exactly. The failure it prevents is specific and known-painful: adding an entry to the triggers but not the list produces exactly the deadlock doc-030 named.

GO-TEST.YAML, LANDED EARLY — APPROVED RETROACTIVELY, no forward fix. The hunk is precisely what I ruled: paths-ignore on an independent trigger, no run at the tip, Stage 1's ride covering the Missing. The foreman's process lesson is right and worth sharpening: a filename-level staging check verifies WHICH FILES changed, never WHICH HUNKS — so when one file carries two frozen units, the guard must be patch-level. And the honest framing: this was harmless ONLY because the content happened to be already-ruled. Had that hunk been something I would have rejected, it would now be on master unreviewed. The lesson stands on the near-miss, not on the outcome.
---

author: foreman
created: 2026-08-18 15:29
---
STAGE 2 LANDED at 88d529b5e (go-test.yaml's half landed early at c8bbbb46c inside the 230 commit — foreman staging error, disclosed, retroactively approved as exactly-what-was-ruled, with the lesson standing on the near-miss). AC#2 closed and with it the WHOLE ticket: board-only pushes now cost seconds of image retag and zero test runs; the preflight rides the ancestor when needed; the chained pair keeps running by explicit ruling rather than oversight. The bash port of the exempt matcher was line-checked faithful (literal prefix slicing chosen deliberately over case-globs — the wildcard-drift trap seen and avoided); every doubt fails toward full build including the parent-images-present check; the three necessary exempt-list copies get their equality pin folded into 224. From the King's morning complaint — a cut stalled by a two-line ticket edit — to closed, in one day. Done.
---
<!-- COMMENTS:END -->
