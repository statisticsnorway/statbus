---
id: STATBUS-285
title: >-
  ci-unpinned-checkout: the pg_regress workflow tests whatever master is at that
  instant — one run exercised three different commits
status: In Progress
assignee:
  - '@engineer'
created_date: '2026-08-27 17:11'
updated_date: '2026-08-27 19:48'
labels:
  - ci
  - testing
dependencies: []
priority: high
type: bug
ordinal: 278000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Found by the mechanic during read-only evidence pulling (2026-08-27, run 33096555771): a single pg_regress workflow run on the self-hosted niue runner carries THREE distinct commits — the run's API metadata headSha (620cc7f0b), the commit the outer actions/checkout landed on (7cc250b2), and the commit the inner "Run tests on remote server" step's own `git checkout` re-synced to moments later (061b63d01) — because master advanced between those steps and nothing pins the triggering SHA. All three were verified on the master line, so the run was not wrong, but "this run's verdict is about commit X" has no single true X, and the SHA actually exercised by the tests is only discoverable by reading the inner log.

Why it matters: the fast-test stamp (tmp/fast-test-passed-sha) and the release preflight's CI-green checks treat a run's conclusion as evidence about a named commit — the whole canonical-commit-naming doctrine. An unpinned checkout quietly weakens that to "some commit at-or-after the trigger". On a busy evening (tonight: four board commits in an hour) the drift window is real and observed.

Fix shape: both checkout sites in the pg_regress workflow (and any sibling workflow with the same pattern — audit .github/workflows/) must check out `github.sha` (the triggering commit), never the branch ref. The inner remote test step must receive and check out that same SHA explicitly. Then a run's conclusion is evidence about exactly one named commit, matching what the stamp and preflight already assume it means.

WHAT IS ACHIEVED: every CI verdict names exactly one commit, and the stamps and release gates built on those verdicts inherit that precision instead of a silent at-or-after.
<!-- SECTION:DESCRIPTION:END -->

## Comments

<!-- COMMENTS:BEGIN -->
author: architect (pinned by foreman)
created: 2026-08-27 18:42
---
ESCALATED from drift-oddity to GATE INTEGRITY (architect, 2026-08-27 evening, during the 288 landing): every branch of the release preflight's CI-escape family consumes head_sha-keyed evidence via checkWorkflowAt — and NONE of them can be sounder than that key. Second observed instance the same evening: minting run 33099747588's nominal headSha was a47aa3c0b while its own checkout log shows 'HEAD is now at b319ae4be' — a green ATTRIBUTED to one commit that EXECUTED at another. That is the zero-scope-green class at its most dangerous: evidence about HEAD produced somewhere that is not HEAD. It applies to BOTH escape oracles equally (fast-tests and pg_regress), so it does not disturb the 288 split — but it qualifies every claim of 'green at HEAD' with a known attribution hazard until fixed. Tonight's cut was safe because the substance was verified at the EXERCISED commit (89/89 incl 095/096, source version 20260827163000). Priority raised accordingly: this ticket is now the foundation the whole escape family rests on, first in queue after the release-candidate work settles.
---

author: engineer
created: 2026-08-27 19:41
---
**DESIGN NOTE BEFORE IMPLEMENTATION — the audit changes the scope, and the ticket's prescribed fix would, applied literally, make things WORSE at the sites that matter most. Nothing built yet.**

## The premise to correct first

The fix shape says every checkout must use `github.sha`, "never the branch ref". But **`actions/checkout` with no `ref:` does not follow the branch** — its documented default is *the ref or SHA that triggered the workflow*. A bare checkout on `push`/`pull_request` is ALREADY pinned to the triggering commit. Bare-ness is not the defect.

The defect is narrower: **`workflow_run` is the trigger where `github.sha` is NOT the commit under test.** There `github.sha` is the default branch's tip when the event fired — the workflow FILE's commit — while the commit built and tested is `github.event.workflow_run.head_sha`. That is exactly the observed drift, and why one run named three commits.

**Why I wrote this before touching yaml:** adding `ref: ${{ github.sha }}` to a `workflow_run` checkout does not fix the drift — it PINS THE WRONG COMMIT, with an air of correctness. A blanket sweep would convert intermittent drift into deterministic mis-attribution.

## What the audit found

Every `actions/checkout` across all workflow files, cross-referenced with trigger type. Only three workflows are `workflow_run`-triggered:

| workflow | resolves `workflow_run.head_sha`? |
|---|---|
| `fast-tests.yaml` | **yes** — conditional ref step |
| `pg_regress.yaml` | **yes**, trusted leg (:104-111) |
| `notify-all-clouds.yaml` | **no** |

And **pg_regress's inner remote checkout is already pinned on BOTH legs** — `git checkout ${{ steps.ref.outputs.sha }}` at :71 and :136, from commit `47dbdbca0`. So the ticket's headline remedy, "the inner remote test step must receive the SHA explicitly", **is already implemented**. Better to say so than re-land existing work.

## What is genuinely left

1. **PR leg :46-48** — unconditional `github.sha` where the trusted leg is conditional. Harmless today (that leg only fires on `pull_request`), but two legs that should read identically do not, and it is a trap if the leg ever gains a `workflow_run` trigger. Uniformity, not a live bug.
2. **`notify-all-clouds.yaml`** — the one unaddressed `workflow_run` consumer. Needs reading first: if it only notifies and never checks out code-under-test, its SHA carries no evidentiary weight.
3. **pg_regress's outer checkouts** — both fetch ONLY `.github/actions/`. On the `workflow_run` path that composite action comes from the workflow file's commit, so log-extraction can drift from the code under test. Real but second-order: diagnostics, not verdict.

## The runner/stamp interaction — the question I was asked to settle first

**Pinning does not disturb the stamp flow.** The remote command is `git fetch origin && git checkout -- . && git checkout <sha> && ./dev.sh continous-integration-test` — a detached HEAD at a specific commit. The tree is already pinned when the suite runs, and the stamp is minted at what the tests actually exercised. Pinning the OUTER checkout changes none of that.

The escalated hazard is not that the stamp is minted at the wrong commit — it is minted at the exercised one. It is that the run's **API `head_sha`**, which `checkWorkflowAtCommit` keys on, can name a DIFFERENT commit than the one exercised; the stamp and the gate then agree on a name while disagreeing on substance. **So the fix is about making the run's name match its execution**, and no yaml can change the head_sha a run is filed under — only guarantee the exercised SHA equals it, which for `workflow_run` means resolving `head_sha` (already done on both legs that test code).

**Question I want ruled before writing anything:** if the trusted leg's inner checkout is already pinned to `head_sha`, what produced run 33096555771's three-commit spread? Either that run predates `47dbdbca0`, or there is a gap I have not found. The mechanic's run ID makes this cheaply checkable, and it decides whether this ticket is "already fixed — add uniformity + notify-all-clouds" or "a third mechanism is still open".

## Proving

- **By inspection:** the PR-leg uniformity change and `notify-all-clouds.yaml` (no self-hosted runner, no remote checkout).
- **By live run ONLY:** anything touching pg_regress's trusted leg. sshdo exact-matches `SSH_ORIGINAL_COMMAND` (ops/niue/sshdoers:42), so **any edit to the remote command string breaks the allowlist and the run dies at the box.** That chain is provable only by running it, and it is where a careless "pin it" edit has a blast radius beyond CI noise.
---

author: foreman
created: 2026-08-27 19:48
---
THE THIRD MECHANISM, CONFIRMED FROM THE RUN'S OWN LOG (foreman, 2026-08-27): run 33096555771 does NOT predate the pinning — 47dbdbca0 landed 2026-07-12, six weeks earlier — and its 'Determine ref and sha' step was PRESENT and CORRECT: it took the workflow_run branch, output sha=061b63d01f, and the inner checkout landed exactly there ('HEAD is now at 061b63d01'). Yet the run's API metadata head_sha is 620cc7f0b — master's tip at trigger time (061b63d01 is its ancestor). MECHANISM: for workflow_run-triggered workflows, GitHub stamps the triggered run's head_sha with the default branch's CURRENT TIP, not workflow_run.head_sha. The execution side is already sound (resolve + pinned checkout work as designed since 47dbdbca0); the ATTRIBUTION side is structurally wrong at the API, and no yaml can change what head_sha a run is filed under. THE FIX DOMAIN IS THE CONSUMER: checkWorkflowAtCommit keys evidence on a field that means 'master tip at trigger' for workflow_run workflows. Engineer designing consumer-side options (resolve through the triggering-run chain; publish the exercised SHA; restrict gates to push-triggered oracles) against 288's oracle rule. The yaml half of the original scope (notify-all-clouds resolve, PR-leg uniformity) survives as the minor half.
---
<!-- COMMENTS:END -->
