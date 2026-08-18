---
id: doc-030
title: 'board-push-ci-decouple: design ruling for STATBUS-219'
type: specification
created_date: '2026-08-18 08:19'
tags:
  - ci
  - release
  - architecture
---
# board-push-ci-decouple — design ruling (STATBUS-219)

Architect ruling, 2026-08-18. Premises verified at writing time against the working tree; every claim below carries its file:line.

## WHAT THIS PART DOES

Before a release is tagged, the prerelease preflight demands proof that the exact commit being tagged is sound. It asks five separate questions of GitHub Actions, all keyed to the tip commit's SHA:

| Gate | Where | What it actually proves |
|---|---|---|
| pg_regress | release.go:191 | the SQL suite passed on this code |
| go-test | release.go:518 | the Go suite passed on this code |
| app-build-lint | release.go:519 | the app builds and lints on this code |
| fast-tests | release.go:520 | the fast suite passed on this code |
| **images** | release.go:453 | **Docker artifacts EXIST in ghcr.io tagged with this SHA** |

The first four are *verdicts about content*. The fifth is *an artifact-existence check* — a different kind of claim, and the distinction is the hinge of this whole design.

On the trigger side, a master push fires Images (images.yaml:16-17); pg_regress and fast-tests then chain off it via `workflow_run: workflows:["Images"] types:[completed]` (pg_regress.yaml:4-6, fast-tests.yaml:39-41). go-test and app-build-lint have their own independent master-push triggers.

## WHAT GOES WRONG

The triggers have no notion of what changed. The team's board lives in the repo, so a two-line ticket edit restarts the entire commit-scope cycle, and because every gate keys on the tip, a cut arriving minutes later waits for tests that a markdown edit made necessary. Observed live 2026-08-18: the v2026.08.0-rc.03 cut refused with "fast-tests is still pending" at bafcb396b, a commit that changed two lines of ticket text.

## THE DETAIL

Three findings decide the shape. The first two rule out the obvious fix; the third makes it unnecessary.

**Finding 1 — Images can never ride an ancestor, and this is not a preference.** The other four gates ask "did this content pass?", and content that is byte-identical to a tested ancestor has demonstrably passed. Images asks "does `ghcr.io/...:<commit_short>` exist?", and no argument about markdown makes an image materialise at a SHA nothing ever published to. The codebase already states the consequence in its own words: the SKIP_IMAGES bypass carries "Docker artifacts NOT verified for this SHA. Deployments may FAIL on stale ghcr.io manifest" (workflow_check.go:104-107). fast-tests confirms the coupling empirically — on the chained path it *pulls* the commit_short-tagged images and `statbus-seed:<commit_short>` rather than building locally (fast-tests.yaml:139-142, :164-165). Riding the Images gate would let a release be cut whose deployment has no images. **Images is excluded from every exemption mechanism, permanently.**

**Finding 2 — the naive trigger fix is worse than the ticket states.** A `paths-ignore: ['.backlog/**']` on images.yaml does not merely leave the preflight with no run at the tip; it also skips the chained pg_regress and fast-tests, *and* leaves the commit with no Docker images at all. A release cut on such a commit would be undeployable. Any trigger-side change must therefore keep publishing an artifact at every master commit — which means a retag path, not a skip. That is real work with a real uncertainty (see Stage 2).

**Finding 3 — the stall is fully curable on the preflight side alone.** The observed refusal was "fast-tests is still pending", which means Images had already completed green at the tip (fast-tests only exists because Images finished). The blocking status was **Pending**, not Missing. So the cut was not waiting on a missing run — it was waiting on a *redundant* run. A preflight that may ride an ancestor's green when the intervening diff is exempt-only cures that stall completely, with no trigger change, no artifact risk, and no dependence on unverified GitHub semantics.

That splits the work into two stages of very different risk, and they must not be conflated.

## THE FIX

### Stage 1 — the exempt ride, preflight-side only (ratify and build now)

**A checked-in exempt list**, `ops/release/ci-exempt-paths.txt`, mirroring the placement of `ops/release/upgrade-sensitive-paths.txt`.

**Matching is an anchored path prefix, NOT substring containment — and this inversion is load-bearing.** `diffTouchesSensitivePath` (release.go:1322) uses substring containment, and its own header explains why: for a *sensitivity* list, over-inclusive matching is the safe direction — a coincidental hit costs one extra test run. For an *exempt* list the failure directions are mirrored: over-inclusive matching means more commits are treated as needing no tests, so an accident here waves untested code into a release. Exempt matching must be under-inclusive. Entry `.backlog/` matches a changed file only when the file's path begins with `.backlog/`. **Do not reuse `diffTouchesSensitivePath` for this**; write a separate helper whose comment states the inversion, so nobody copies the wrong conservatism forward.

**The list starts at exactly one entry: `.backlog/`.** An exempt path is one whose content cannot change any test outcome, any build artifact, or any runtime behaviour. `.backlog/` qualifies — it is markdown read only by the backlog tooling. `doc/` is the obvious next candidate and is probably safe (its only known gate, `.claude/hooks/doc-db-freshness.sh`, is a local commit hook, not a CI input), but it ships as its own argued, ratified addition rather than riding in on this one.

**The walk.** When a verdict gate is not green at the tip — Missing *or* Pending or Failed — the preflight walks first-parent ancestors of the tip, nearest first, bounded at 50 commits. For each candidate C it computes the **direct** `git diff --name-only C..tip` and asks whether every changed file is exempt. The first candidate that is exempt-clean *and* green for that gate is the ride target. A direct diff, never per-hop induction — the same "correct by construction" reasoning `checkUpgradeArcHarnessGate` already documents for its RC walk, and strictly more capable: a pair of commits that adds and then reverts code yields an empty direct diff, and riding there is sound because the trees are identical.

**Refusal is unchanged wherever the ride does not apply.** A non-exempt diff, an exhausted walk, or no green ancestor all refuse exactly as today. Images refuses as today, always.

**Output is loud, never silent.** Print the ride target's SHA, how many commits were ridden, and every file in the diff that justified it — the same standard the arc gate's RIDE printing already holds.

**Two tests pin the invariants:** a non-exempt file anywhere in the diff must refuse; and `ops/release/ci-exempt-paths.txt` must not itself match any entry in its own list, so that changing what counts as test-irrelevant can never ride a prior green (AC#5, mechanically enforced rather than remembered).

### Stage 2 — the trigger-side saving (design ratified, build gated on one probe)

Stage 1 removes the stall; Stage 2 removes the wasted CI minutes. It is worth doing and it is strictly harder.

The shape: images.yaml decides internally. Diff against the parent — non-exempt changes take the normal build path; exempt-only changes take a **retag** path that copies the parent's manifests to the new SHA in seconds. The artifact invariant "every master commit has images at its SHA" then holds unconditionally, so nothing downstream — deployment, upgrade, arcs, install — needs to change at all. That containment is the reason to prefer retag over any skip.

The chained pair is the hard part, and it must not be solved by letting them self-report. Because `workflow_run` fires on completion regardless, pg_regress and fast-tests will still start. If their jobs skip, the run's conclusion decides everything: a run that concludes **success** with nothing executed is a phantom green, the exact softness STATBUS-199 and STATBUS-215 exist to refuse, and it would let the preflight pass while hiding the ride from the operator. A run that concludes **skipped** is harmless — `CheckWorkflowAtCommit` treats non-success as not-green (workflow_check.go:94), Stage 1's ride then makes the decision explicitly and loudly, and the doctrine holds.

**Everything in Stage 2 rests on which of those two GitHub produces for an all-jobs-skipped run, and we do not know.** Our one piece of local evidence points the wrong way: run 32009980725 concluded SUCCESS with the arc matrix skipped — though other jobs in it did run, so it does not settle the all-skipped case. This is not reasoning's to settle. **Probe it before building Stage 2**, on a scratch branch, the same one-shot method that settled STATBUS-215: a workflow whose only job is skipped, then read the run's conclusion. If it is `skipped`, Stage 2 proceeds as described. If it is `success`, the chained pair cannot be skipped internally at all, and Stage 2 shrinks to the independent triggers (go-test, app-build-lint) plus the images retag, leaving pg_regress and fast-tests running redundantly on board commits — which Stage 1 has already made harmless to the operator.

## WHY THAT HELPS

Board activity is how this team coordinates; it should cost nothing and block nobody. After Stage 1 a cut proceeds the moment the code state is proven, no matter how much ticket text has landed since — and the guarantee gets *sharper*, not looser: today "green at tip" is a proxy for "this code is tested", and the ride replaces the proxy with the actual claim, evidenced by a printed diff. After Stage 2 the redundant runs stop being paid for at all.

The two stages are separable on purpose. Stage 1 is self-contained, carries no unverified premise, and cures the observed pain; Stage 2 is a cost optimisation resting on a fact we must go and measure. Shipping them together would put a known cure behind an open question.
