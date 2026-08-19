---
id: STATBUS-249
title: >-
  evidence-marks: a skip must name what it inherited, and cannot inherit from
  something never proven
status: To Do
assignee: []
created_date: '2026-08-19 09:06'
updated_date: '2026-08-19 09:51'
labels:
  - release
  - ci
  - quality-gate
dependencies: []
references:
  - .github/workflows/release-fleet-orchestrator.yaml
  - cli/cmd/release.go
  - ops/release/upgrade-sensitive-paths.txt
priority: high
type: enhancement
ordinal: 242000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Our expensive test suites may be skipped when a candidate changed nothing they cover — the candidate inherits the previous one's proof instead of re-renting 31 machines to learn the same thing. That is a sound saving, and it is currently built on an assumption nobody checks: **that the previous candidate was actually proven.** When it was not, the chain inherits from nothing and reports success.

THE SPECIMEN, and it is not hypothetical. rc.06's fleets were cancelled mid-chain, so its arcs never ran. rc.07 was then cut, compared itself against rc.06, found no upgrade-sensitive change, skipped the arc fleet — and its chain concluded **success** (Release Fleet Orchestrator run 32226442525 at commit ed0052d5e). Nothing had been proven about upgrade arcs at either candidate. The word "success" was reporting the absence of a reason to run, not the presence of a result.

WHAT IS ACTUALLY WRONG: the skip is keyed on **the previous TAG** rather than on **evidence**. `PREV_RC` is derived as "the RC tag before this one" and the diff is taken against it (release-fleet-orchestrator.yaml, the `decide-upgrade-sensitivity` job). A tag is a name, and a name says nothing about whether anything ran. The comment above that logic describes the intent exactly right — "inherit the previous release's proof instead" — and the code cannot tell whether a proof exists.

**A NECESSARY CORRECTION TO THE SEVERITY, verified rather than assumed: this could not have caused a bad promotion.** The stable release gate re-derives everything independently and refuses to ride a prior candidate unless that candidate's run is green AND every required arc job actually ran and succeeded, walking further back when it is not (cli/cmd/release.go, `checkUpgradeArcHarnessGate` and the path-sensitivity walk at 2072-2092). An unproven predecessor fails that test and is skipped as an anchor. So the file's claim that a wrong answer here "only costs an avoidable/skipped fleet dispatch, never a bad promotion" is TRUE, and it should not be reported as a near miss.

What it damages instead is the signal people act on. A chain that says success is read as "the tests passed", and here it meant "no test was owed against a predecessor that was itself never tested". The promotion gate would eventually refuse, but only later, after everyone had already believed the chain. **A green that means nothing is a defect even when a second gate catches it** — it teaches people the wrong thing about what green means, and it is the same shape as every other zero-scope green we have found: a check reporting on an examination it never performed.

THE FIX — MARKS, NOT NAMES. Each scenario that completes leaves a **durable, discoverable mark**: this scenario, at this code-state, passed. A later candidate asking "must I run this?" looks for the mark rather than reasoning about tags. Then:

- **Inheriting from something never proven becomes inexpressible.** You cannot find a mark that was never written. The false assumption is not detected and reported — it stops being representable, which is why this is a structural fix rather than an added check.
- **Granularity becomes per-scenario.** Today the decision is all-or-nothing for a whole fleet. Marks are per scenario, so a candidate can inherit the twenty-eight scenarios it did not touch and run the three it did.
- **Any verdict that inherited must SAY SO, naming the source** — "success — arcs inherited from &lt;commit&gt;" — never a bare success. A verdict that does not distinguish "ran and passed" from "did not need to run" is not reporting its own scope, which is the defect that produced the specimen above.

This is the per-scenario stamp design already ratified for the install-recovery harness, generalized to the whole chain. Worth noting that the principle is not new to this codebase and is not being invented here: the Go release gate ALREADY requires a complete, actually-succeeded anchor before it will let anything ride a prior green. This entry propagates a discipline we already have, from the layer that got it right to the layer that got it wrong.

WHY THAT HELPS: the saving is kept and the lie is removed. A chain's verdict comes to mean exactly what it says — either this was proven here, or it was proven there and here is where — and no candidate can ever again inherit a proof that does not exist.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Each completing scenario writes a durable, discoverable mark identifying the scenario and the code-state it passed at
- [ ] #2 The skip decision is made by looking for a mark, never by comparing tag names or assuming a predecessor was proven
- [ ] #3 Inheriting from an unproven predecessor is structurally impossible — no mark exists to be found — rather than being detected and reported
- [ ] #4 Inheritance is per-scenario: a candidate can inherit the scenarios it did not touch while running the ones it did
- [ ] #5 Any verdict that inherited or skipped names what it inherited from; a bare 'success' covering un-run work is a failure of this entry
- [ ] #6 A superseded or cancelled chain writes no marks for work that did not complete, so nothing downstream can ride it (STATBUS-246)
- [ ] #7 The rc.07 specimen is replayed against the new mechanism and produces a verdict that names its scope instead of a bare success
- [ ] #8 Marks are composable from a local run or from CI, per the ratified install-recovery stamp design
<!-- AC:END -->

## Comments

<!-- COMMENTS:BEGIN -->
author: foreman
created: 2026-08-19 09:28
---
KING APPROVED 2026-08-19 (dialogue presentation, fourth of the sitting), with two rulings and one question answered:
(1) WORDING RULED: the message form is "covered by" — "test <X> is already covered by <Y>" — consistent with the preflight's existing "also covers" vocabulary; fold into every skip/inherit message.
(2) CODE REUSE — his question "can the same Go logic run in the gate AND in the job, a small binary from the same library, same by design not by chance?" — foreman's answer, delivered: YES — chain jobs already build/fetch the sb binary (several workflows do; RCs publish it as a release asset), so the covered-by decision becomes a subcommand (shape: ./sb release covered <scenario> <commit>) built from the SAME library code as the promotion gate's anchor-and-walk-back logic. One algorithm, two call sites. ARCHITECT TO VERIFY in the fold: the mark-store location/design (the ratified per-scenario stamp design is the starting point) and that the gate's existing functions factor cleanly into a shared library path.
(3) The severity correction was acknowledged ("nice finding").
---

author: architect
created: 2026-08-19 09:49
---
STORE LOCATION RULED: **there is no new store.** The marks already exist — they are the workflow run's per-job records, keyed by head_sha, and the release gate already queries them. Option (d), the shape not enumerated.

A mark for scenario X at code-state Y IS: a job named X, with conclusion success, in a run at head_sha Y. That is not an analogy; it is what `WorkflowJobsCompleteAtCommit` already reads.

MEASURED, because the engineer is right to refuse unmeasured platform rules and the durability claim is the whole ruling:
- The OLDEST install-recovery run still visible is run 26464982033 at 9226395ae, created 2026-05-26 — twelve weeks old. Querying `actions/workflows/install-recovery-harness.yaml/runs?head_sha=9226395ae…` still returns total_count=1, and `runs/26464982033/jobs` still returns job names with conclusions. Run and job metadata therefore survive far beyond the 14-day ARTIFACT retention that correctly disqualified artifacts. The artifact cliff is real; it simply does not apply to the records we would actually read.
- Granularity is already per-scenario: a current run (32227385996) reports 18 jobs, one per scenario, named exactly by scenario — `1-boot-concurrent-install | success`, `5-install-stage-b-pool-exhaustion | success`, and so on.
- Never-exists-for-incomplete-work (AC#6) is already satisfied: a cancelled or skipped job carries a non-success conclusion and lands in the existing Unsuccessful bucket. rc.06's cancelled arcs could not be mistaken for proof by this store, which is precisely why the Go gate was immune to the rc.07 defect while the chain was not.

WHY THIS BEATS ALL THREE ENUMERATED OPTIONS: it sidesteps rule (T) entirely, because nothing is pushed — no probe needed, and the measured hazard becomes irrelevant rather than managed. It needs no statuses:write, no token story, no new permission. And it introduces NO NEW PLATFORM DEPENDENCY: the release gate already bets on exactly this API and this retention, in checkWorkflowAtCommit and in the path-sensitivity walk. We are not accepting a new risk; we are declining to build a second store for a question the first one already answers.

THE LOCAL HALF (AC#8) keeps the ratified stamp pattern, which the engineer already identified as the right composability shape: a local stamp file records locally-run scenarios, the CI job record covers CI-run ones, and ONE lookup consults both. That is today's tmp-stamp-plus-CI-query pattern, generalized per-scenario — unchanged in shape, only in granularity.

ONE CORRECTION THE LOOKUP MUST MAKE, and it is not optional. `checkWorkflowAt` returns the FIRST GREEN run at a head_sha (cli/internal/release/workflow_check.go:152-157), not all of them. For a per-scenario question that is wrong: `covered(scenario, commit)` must ask whether ANY completed run at that commit contains a successful job of that name — union across runs, not first-run-wins. This also fixes at the library level the smoke-run-versus-full-run collision that doc-034 finding B otherwise handles only by giving smoke its own workflow identity. Do both: separate identity, and union semantics.

CONSEQUENCE FOR THE WORK IN FLIGHT: the engineer's current extraction of the gate's decision logic from its presentation is not preliminary to 249 — it IS 249's implementation. One algorithm, two call sites, over a store that already exists.
---

author: engineer
created: 2026-08-19 09:51
---
**WAVE A1 PART 1 FROZEN: the shared algorithm exists and is RED-verified. Part 2 (the mark store + the subcommand) is BLOCKED on the architect's location ruling — question sent with evidence, not waiting idle.** Two new files, both mine, no collision with A2's sweep: `cli/internal/release/coverage.go` (230 lines), `cli/internal/release/coverage_test.go` (215).

**ARCHITECT'S VERIFICATION ITEM 2 — ANSWERED: the gate factors cleanly, with one named exception.** Checked, not assumed:
- `loadUpgradeSensitivePaths` (release.go:1640), `diffTouchesSensitivePath` (:1661) and `upgradeArcNamesAtCommit` (:1707) are already **pure — zero `fmt.Print` between them**. They move or inject as-is.
- `workflowJobsCompleteAtCommit` + `JobsCompleteness` already live in the library (`internal/release/workflow_check.go:236`).
- **The exception: the walk itself does NOT factor as it stands.** It is inline in `checkUpgradeArcHarnessGate` (release.go:2074-2130) with the decision interleaved with operator-facing printing at every branch. A second caller could only have re-implemented it — and a re-implementation that drifts is how one question gets two answers. Extracting decision from presentation IS the work of "one algorithm, two call sites", so that is what I built.

**WHAT IS BUILT — `DecideCoverage`, pure (no printing, no I/O), inputs injected as functions.** It returns a VERDICT the caller renders, so gate and subcommand cannot drift in either the decision or the sentence.
- **THREE-WAY answer, deliberately not a boolean:** `proven-here` / `covered-by` / `not-covered`. Collapsing the two “yes” answers is precisely the specimen's defect — a verdict that cannot tell them apart cannot name what it inherited (AC#5).
- **Wording per the King's ruling:** `Summary()` renders `test <X> is already covered by <Y>`, and a covered-by verdict that somehow names nothing prints an **accusation containing “BUG”** rather than a plausible blank sentence. Pinned as a property.
- **Evidence, never tag order** (AC#2/#3): the anchor is the newest prior candidate with EVIDENCE. Injecting `EvidenceAt` is what lets the same walk serve today's run-completeness basis and tomorrow's marks.
- **STATBUS-199 D2 preserved**: the walk STOPS at the newest anchor with evidence when a sensitive path changed — riding an older anchor whose larger diff range contains the same change would be worse, not better.
- **Unevaluable ≠ unproven**: a candidate we could not resolve or read is RECORDED in `EvidenceErrors`, never silently counted as “no evidence”. Silently dropping it would be a walk claiming an examination it did not perform — the same zero-scope shape in a new costume.
- **Missing inputs REFUSE** rather than answering “not covered”.

**ORACLES — RED-VERIFIED by mutation, three arms:**
1. **The rc.07 specimen replayed as a unit (AC#7):** rc.06 has no evidence (cancelled), rc.05 does. Mutating the walk to select by tag ORDER instead of evidence FAILS with “THE SPECIMEN: inherited from rc.06, which was cancelled and never proved anything”. The green path asserts the verdict NAMES rc.05 in the ruled wording.
2. **Collapsing proven-here into covered-by** FAILS.
3. **Silently dropping an unevaluable candidate** FAILS.
Also pinned: nothing-ever-proven ⇒ not covered (AC#3) and the walk reports how many candidates it examined.

**VERIFY CHAIN:** `go test -count=1 ./internal/release/` ok; `gofmt -l` clean on both files; `golangci-lint run ./internal/release/...` 0 issues.

**WHAT REMAINS, and why it is not guesswork:** the mark WRITE side, the `./sb release covered` subcommand, and rewiring the gate onto the shared path all need the evidence source — i.e. the store. Three facts I established for that ruling: today's `tmp/*-passed-sha` stamps are local and gitignored (right composability pattern, cannot answer across machines); **artifacts are disqualified** (14-day retention at `upgrade-arc-harness.yaml:829` and `install-recovery-harness.yaml:182/523`, 30 at `test-install.yaml:199` — a store that forgets turns an inherited proof back into a bare success on a timer); and nothing here writes statuses, check-runs, notes or custom refs today. **Named hazard for the obvious git-ref shape:** STATBUS-236 measured rule (T) — a pushed ref is refused when its `.github/workflows/` tree differs from the default branch, proven by arm (a) on a ref at an already-existing commit with zero new commits. Marks are written at RC commits, whose workflow trees routinely differ within hours. Whether (T) governs non-branch refs is UNMEASURED, and I will not design against an unmeasured platform rule twice.
---
<!-- COMMENTS:END -->
