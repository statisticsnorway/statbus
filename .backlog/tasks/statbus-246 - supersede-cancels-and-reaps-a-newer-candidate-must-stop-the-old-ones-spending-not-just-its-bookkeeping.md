---
id: STATBUS-246
title: >-
  graceful-supersede: a newer candidate should stop the old one at the next
  joint, not kill it mid-sentence
status: To Do
assignee: []
created_date: '2026-08-19 07:14'
updated_date: '2026-08-19 10:19'
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
<!-- COMMENTS:END -->
