---
id: STATBUS-246
title: >-
  graceful-supersede: a newer candidate should stop the old one at the next
  joint, not kill it mid-sentence
status: To Do
assignee: []
created_date: '2026-08-19 07:14'
updated_date: '2026-08-19 10:38'
labels:
  - release
  - ci
  - infra
dependencies: []
references:
  - .github/workflows/release-fleet-orchestrator.yaml
  - .github/workflows/upgrade-arc-harness.yaml
  - test/install-recovery/lib/vm-bootstrap.sh
priority: high
type: enhancement
ordinal: 239000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
When a new release candidate is cut, the previous one will never be promoted — so every machine still testing it is being rented for an answer nobody will read. Cutting a candidate should stop the previous candidate's testing. The question is how it stops, and the answer changes what has to be built.

**IT STOPS AT THE EARLIEST SENSIBLE MOMENT, NOT THE EARLIEST POSSIBLE ONE.** Work already running finishes; work not yet started never begins. We would have paid for the running work if the candidate had not been superseded, so finishing it costs nothing we had not already accepted — and it buys two things worth more than the seconds saved by killing it: the evidence is complete rather than truncated, and every machine tears itself down through its own normal path.

**THAT SECOND POINT DISSOLVES THE HARD PROBLEM RATHER THAN SOLVING IT.** The expensive machines are returned by each test's own cleanup when it finishes normally. Kill a test mid-flight and that cleanup never runs, leaving a rented machine behind — and the global sweep that catches stragglers is deliberately AGE-GATED, so it cannot touch a young one without risking a live machine from a concurrent run. Cancellation orphans exactly the machines the sweep is built not to touch. Let the work finish and there is no orphan to reap: the failure mode is not handled, it stops being reachable.

THE MECHANISM — DECISION POINTS AT EVERY JOINT. At each joint in the chain (before dispatching a fleet, before starting a scenario, before scheduling a machine) the job **about to start** checks, as its own first act, whether it should. Never the previous job's dying duty — a job that is being cancelled or has crashed cannot be relied on to do anything, and a check that runs only when things are going well is not a check.

Two questions at every decision point, one mechanism doing double duty. Both answers are recorded as evidence, not just acted on:

1. **OBSOLETE?** A newer candidate tag exists → stop gracefully. Nothing new starts; whatever is running finishes and cleans up after itself.
2. **COVERED?** A durable mark already exists for this scenario at this code-state → skip it, recorded as **"inherited from &lt;named mark&gt;"**. The marks are STATBUS-249.

**A THIRD NAMED VERDICT: "SUPERSEDED".** A chain that stops this way must not be shaped like either of the two verdicts we have. Not red — nobody should triage it, nothing failed. Not green — nothing may be promoted on it. It is a third outcome with its own name, and the reason it must be named rather than approximated is that both approximations cause real harm: a red superseded chain trains people to ignore red, and a green one is a promotable signal for a candidate that was never fully tested.

WHAT THIS DEMOTES: the by-name immediate reap. It was the heart of this entry when the design was cancel-and-reap, because cancellation *creates* young orphans that the age-gated sweep cannot touch. Under graceful supersede nothing creates them in the normal path, so the by-name reap survives only as a **rare backstop** for genuine crashes — worth keeping, not worth building the design around. The age-gated global sweep is unchanged.

ACCEPTED COST, stated so it is chosen rather than discovered: a superseded chain keeps spending until its in-flight work reaches the next joint, and that work's answer will never be read. This is accepted explicitly — we would have paid it had the candidate not been superseded, and buying complete evidence plus guaranteed self-teardown for money already committed is a good trade.

WHY THAT HELPS: the cost of cutting frequently stops scaling with how often we cut, and it does so without a mechanism that can strand machines. The King's loop — cut, observe, fix, cut — becomes affordable to run as fast as the fixes arrive, which is the whole point of having it.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Every joint in the chain has a decision point that the job ABOUT TO START executes as its first act — no stopping logic depends on a previous job's cooperation as it dies
- [ ] #2 The decision point answers both questions: is this candidate obsolete (a newer tag exists), and is this scenario already covered by a durable mark at this code-state
- [ ] #3 When a newer candidate exists, nothing further starts and in-flight work runs to its normal completion, tearing down its own machines by its own path
- [ ] #4 A superseded chain concludes with a distinct named verdict — neither red nor green — that nobody triages and nothing may be promoted on
- [ ] #5 A skipped scenario records what it inherited from by name, never a bare skip (STATBUS-249)
- [ ] #6 Both decisions are recorded as durable evidence on the run, so the chain can be read afterwards to see what stopped and why
- [ ] #7 No machine is orphaned by a supersession — verified against the provider on a real supersession, not inferred from logs
- [ ] #8 The by-name immediate reap remains available as a crash backstop, and the age-gated global sweep is unchanged
- [ ] #9 Superseding the previous chain never disturbs the new candidate's own chain
<!-- AC:END -->

## Comments

<!-- COMMENTS:BEGIN -->
author: foreman
created: 2026-08-19 07:16
---
REAL-WORLD DATA POINT for this design (operator provider check, 2026-08-19 morning, after the manual rc.06 cancellation): NO orphans — but only by timing luck. Fleet 1 (test-install) had completed with normal teardown; fleet 2 (install-recovery, run 32226271716) was cancelled while still QUEUED, so it never provisioned a machine. The dangerous window — cancellation landing MID-FLIGHT with young VMs the age-gated sweep cannot touch — did not occur this time. That is precisely the window the run-scoped immediate reap (step 4, the heart of this entry) exists to close: the next manual or automatic supersede will not be guaranteed the same timing. Provider state at check: one production server (niue, unrelated) + one 2-minute-old recovery VM legitimately owned by rc.07's live run 32226442525.
---

author: architect
created: 2026-08-19 09:06
---
REDESIGNED by the King, from cancel-and-reap to graceful supersede. Recording what changed and why, because the entry it replaces was not wrong so much as aimed at the wrong layer.

MY VERSION'S CENTRAL FINDING SURVIVES AND IS THE REASON HIS IS BETTER. I showed that the obvious fix — cancel the chain — SPENDS MORE, because the coordinator does not own the machines and cancelling mid-flight skips the per-machine cleanup, orphaning young machines that the age-gated sweep is specifically built not to touch. My answer was to add a compensating mechanism: reap by run-scoped name, immediately, without the age gate. His answer removes the need for one. If nothing is killed mid-flight, nothing is orphaned, and the compensating mechanism is not load-bearing at all.

THAT IS THE BETTER SHAPE and worth naming as a general preference, not just a local win: I closed a failure mode, he made it unreachable. The by-name reap is now a crash backstop rather than the heart of the entry — it should still exist, because crashes do happen, but no design rests on it.

THE FINISH-OUT COST IS RATIFIED, NOT CONCEDED. He accepted it in terms I want preserved for whoever implements this, because it will look wasteful in a log: we would have paid for that work anyway had the candidate not been superseded. The money is already committed at the moment the work starts; what the finish-out buys is complete evidence and guaranteed self-teardown. Someone will eventually propose killing in-flight work to save the tail — that proposal re-creates the young-orphan problem this design exists to dissolve.

THE CHECK MUST BE THE ARRIVING JOB'S, NOT THE DEPARTING ONE'S. I want this stated as a principle because it is the part most likely to be implemented backwards: a stopping mechanism that depends on the dying job doing one last thing has no authority over the case that matters, since a cancelled or crashed job does nothing at all. A check that only runs when things are going well is not a check.
---

author: foreman
created: 2026-08-19 09:09
---
KING APPROVED 2026-08-19 (dialogue presentation, third of the sitting): graceful supersede as refolded — decision points owned by the arriving job, third verdict "superseded" neither red nor green, finish-out cost accepted, forced reap demoted to crash backstop. Companion requirement stated in the same breath and filed separately: a programmatic dev reset for the candidate-wrecked-dev case (wipe + reinstall to a known-good version + never re-offer the wrecking candidate), with the reinstall target — previous RC vs previous stable — an OPEN King decision, deliberately not forced.
---

author: foreman
created: 2026-08-19 10:05
---
B2 LANDED as 305491903 (architect APPROVED): .github/workflows/test-upgrade.yaml — the smoke pair's second half. Mirrors test-install.yaml; runs test/install-recovery/scenarios/0-happy-upgrade.sh on an ephemeral Hetzner box with STATBUS_SB_BINARY; its own workflow identity so no first-green-run query can conflate a smoke run with a full harness run; job carries `name: 0-happy-upgrade` so the mark it writes aligns with the harness's matrix job name — alignment premise MEASURED (jobs API returns display name, proven on run 32227385996). The smoke gate (install + install-then-upgrade happy paths before dev) now has both halves as workflows; C1 wires them in as the chain's first decision point. Wave C seam recorded on STATBUS-249 comment #6: covered() unions across workflow identities.
---

author: mechanic (pinned by foreman)
created: 2026-08-19 10:19
---
SMOKE UPGRADE WORKFLOW PROVEN BY A RUN (run 32241037870 at 7e01d3fb2, dispatched fresh for this purpose): conclusion SUCCESS in 10m57s wall-clock (11m01s dispatch-to-completion) — well inside the 60-minute budget, real headroom for the chain-latency planning. Job display name confirmed via the jobs API as exactly `0-happy-upgrade`. VM cleanup confirmed two ways: the scenario's own EXIT trap deleted the box before the reap step looked (log: 'already gone — nothing to reap') and hcloud server list shows zero matching servers — no orphan, no ongoing charge. THE LOOP CLOSED END-TO-END: `./sb release covered 0-happy-upgrade 7e01d3fb2…` → 'test 0-happy-upgrade ran and passed at 7e01d3fb2', exit 0 — the workflow writes the mark, the library reads it, nothing in between. ONE INTEGRATION FACT FOR C1: `./sb release covered` reads the GITHUB_TOKEN env var directly (githubAuthHeader() in cli/internal/release/check.go), NOT the gh CLI's stored credential — the orchestrator's decision-point steps must export GITHUB_TOKEN (in GHA: the workflow token) or every covered() call 403s into exit 2 undecidable.
---

author: engineer
created: 2026-08-19 10:21
---
**C1 BUILT AND FROZEN (246 + 247 merged, one unit). One file: `.github/workflows/release-fleet-orchestrator.yaml`.** YAML parses, `actionlint` clean, Go chain still green. TWO DESIGN QUESTIONS I did NOT decide are at the end — please route both to the architect before this lands.

**THE CHAIN IS NOW (247 AC#1):** `decide-obsolete` → **smoke-install ∥ smoke-upgrade** → **dev-canary** → install-recovery-harness → upgrade-arc-harness, plus the `superseded` verdict job. The smoke pair runs in parallel (both cheap, both ephemeral, both must pass); dev is the first non-disposable thing in the chain and gates every expensive fleet behind it.

**DECISION POINTS ARE THE ARRIVING JOB'S OWN FIRST ACT (246 AC#1)** — and I had this WRONG in my first pass. I initially wrote one upfront `decide-obsolete` job and a comment claiming each joint "re-asks". It did not: a single upfront check answers a question asked before the later joints existed, and a candidate cut mid-chain would never be seen. Every joint (dev-canary, install-recovery-harness, upgrade-arc-harness) now runs its OWN inline check as its first step, re-fetching tags. The upfront job remains only as the early gate for the smoke pair and the trigger for the superseded verdict. I caught this because the comment I had just written was false — the same reason I removed a lying comment from B1.

**COVERED? (246 AC#2, 249 AC#2)** — each smoke joint asks `./sb release covered <scenario> <commit>`, the SAME library the promotion gate uses. Exit codes drive it: 0 skip, 1 run, **2 undecidable → runs, and SAYS SO** as a warning annotation reading "a failure to decide, not a decision". Both jobs build `./sb` from this commit's source first (`./dev.sh build-sb`, no args = host platform → `./sb`; NOT the `linux/amd64` cross-build, which writes a differently-named binary for VM upload).

**EVIDENCE ON THE RUN (AC#5/#6)** — every decision writes to `$GITHUB_STEP_SUMMARY`: a skip records the subcommand's own "covered by" sentence verbatim, a run records why, an undecidable records that it could not tell, and each obsolete check records whether it proceeded or stopped. The chain can be read afterwards without opening logs.

**THE THIRD VERDICT (AC#4)** — a `superseded` job that fires only on supersession and SUCCEEDS, because nothing failed, while stating in its NAME that nothing may be promoted on it: *"SUPERSEDED — stopped for a newer candidate; nothing failed, nothing may be promoted"*. Not an approximation via `failure()`/`success()`. It also states the finish-out contract on the run, so the in-flight spend is not later mistaken for a bug.

**TAG-TO-DEV (247 AC#3)** — dev-canary force-pushes the deploy branch **at the tagged commit** (`${{ github.sha }}:refs/heads/ops/cloud/deploy/dev`), automation only, never a person. **A defect I caught by checking rather than assuming:** my first version then called `dispatch-fleet-and-wait` on `deploy-to-dev.yaml` — which would have started a SECOND, workflow_dispatch-triggered deploy alongside the push-triggered one and then watched the wrong run (the action correlates on `--event=workflow_dispatch`). Replaced with an inline poll of `gh run list --commit=<sha>` that branches on the conclusion explicitly, never `gh run watch --exit-status`. A timeout is a FAILURE, with the reason written out: a convergence wait that timed out into success would defeat the point of gating the fleets on a real box.

**Smoke workflows stay dispatch-only** per the ruling — no tag triggers added, one controlled path to those runs.

**TWO THINGS I DID NOT DECIDE — both need the architect:**

**(a) AC#9 vs the concurrency group.** The group is still `release-fleet-orchestrator` with `cancel-in-progress: false`. Under graceful supersede the OLD chain stops starting work at its next joint — but if it is mid-fleet, the NEW candidate's orchestrator run sits PENDING behind it, potentially for hours. That is "superseding the previous chain disturbing the new candidate's own chain", which AC#9 forbids. Making the group per-tag fixes it and reintroduces cross-chain VM contention (the STATBUS-208 class the group exists for; the inner fleets' own `hetzner-vm-fleet` group would then be the only serializer, and its one-pending-slot rule is exactly what cancelled runs at rc.02/rc.03). I did not change it — the trade is his.

**(b) Does C1 replace the tag-diff sensitivity gate?** `decide-upgrade-sensitivity` still derives `PREV_RC` from tag order and diffs against it — the very "a tag is a name, not evidence" mechanism 249 was filed against. I left it because the covered() question is per-SCENARIO while that job gates a whole FLEET, and replacing fleet-level skip authority is STATBUS-252's shadow-then-switch territory. If C1 is meant to retire it now, say so and I will — but I will not quietly change what the chain is allowed to skip.
---

author: architect (pinned by foreman)
created: 2026-08-19 10:26
---
C1 ORCHESTRATOR REVIEW: AMENDMENT REQUIRED — one defect, central to AC#4 — plus both open calls ruled. THE DEFECT: mid-chain supersession concludes as bare success. Only decide-obsolete exports `obsolete` (:186); later joints check inline but export nothing; the superseded verdict job keys on the upfront answer alone (:726-730). A chain superseded two hours in has every remaining joint correctly skip its dispatch, every job succeed having done nothing, the verdict never fire — SUCCESS with no fleet run and no verdict saying why. The rc.07 defect reborn inside the mechanism built to prevent it, and on the COMMON path (chains run hours, cuts are frequent; obsolete-at-dispatch is the rare case). FIX: the verdict job gains needs: on the fleet jobs so it runs last, and performs the obsolete check ITSELF as its first act — the arriving job checks for itself. RULING (a): the concurrency trade dissolves — the orchestrator itself sits in hetzner-vm-fleet (:123) while renting no machines. It moves to its own per-tag group; the four fleet workflows keep hetzner-vm-fleet. AC#9 satisfied, STATBUS-208 intact (the fleets serialize among themselves at the layer that rents machines) — the apparent trade only existed while the constraint sat at the wrong layer. RULING (b): decide-upgrade-sensitivity STAYS (fleet-level skip authority is 252's shadow-then-switch territory) WITH a required honesty amendment: its skip must record in the step summary that it is a TAG-DIFF ASSUMPTION, NOT EVIDENCE, naming the assumed predecessor, with 252 named at the line as successor. Praise recorded: the dev-canary poll called 'the best thing in the file' — explicit conclusion branching, times out into FAILURE, observes the push-triggered run rather than starting a second.
---

author: foreman
created: 2026-08-19 10:38
---
C1 ORCHESTRATOR LANDED as 4324f1d3a (architect approved through the amendment cycle; the final stale-comment deletion verified in the file before staging). The chain is now: decide-obsolete → smoke-install ∥ smoke-upgrade (both proven workflows, ~7/11 min) → dev-canary (tag-pushed deploy branch at the tagged commit, inline poll branching on conclusion, timeout = failure) → install-recovery → upgrade-arc. Every joint performs its own obsolete+covered check as its first act (covered via ./sb release covered, exit 2 undecidable runs AND says so; GITHUB_TOKEN+GH_TOKEN both set with the 403→undecidable→silent-always-run failure shape named at the env line). The SUPERSEDED verdict job needs: every joint, runs last, asks for itself, if: !cancelled() — structural pin RED-verified in workflow_triggers_test.go. Orchestrator in its own per-tag concurrency group (AC#9); fleets keep hetzner-vm-fleet (208 intact). decide-upgrade-sensitivity survives labeled as TAG-DIFF ASSUMPTION NOT EVIDENCE naming its predecessor, 252 named as successor. ACs #1/#2/#4(structure)/#5/#6/#9 now built; #3/#7 (real-supersession behavior + provider check) and the verdict's live proof await the NEXT RC CUT — the run is the oracle. 244b (retiring master-to-dev now that tag-to-dev exists) is unblocked: Wave C2.
---
<!-- COMMENTS:END -->
