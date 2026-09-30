---
id: STATBUS-425
title: >-
  All release gating on the LXD box: smoke builds the checkpoints; faults and
  upgrade arcs fork from them
status: In Progress
assignee: []
created_date: '2026-09-28 13:07'
updated_date: '2026-09-30 15:14'
labels:
  - ci
  - lxd
  - release
dependencies: []
priority: high
ordinal: 374200
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
The 4/4 upgrade-arc stage boots one Hetzner CX23 per arc, max-parallel 2 (project core quota): 35 arcs x ~11 min = ~3.5 h (green run 35975471099: 08:28-12:07; rc.14 run 36414310454: 11:13-12:50). STATBUS-417 moved only the fault fleet to LXD. Move the arcs onto the LXD box the same way: ordinary arcs fork the candidate's installed checkpoint (A = candidate), 6+ at once; special bases (schema-floor d53731ec5, pre-rename 730b5001c) get their own install. Parity per owner ruling for 417: LXD arc verdicts match the Hetzner arc verdicts at the same commit. Gate: ./sb release stable requires the LXD arc run green at the RC commit; the Hetzner run-arc matrix is retired.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Every arcs/*-arc.sh runs on the LXD box from one CI job with bounded parallelism
- [ ] #2 Verdicts match the Hetzner arc run at the same candidate commit
- [ ] #3 Orchestrator 4/4 and the stable gate use the LXD arc run; the Hetzner run-arc matrix is deleted
- [ ] #4 Full arc suite wall time under 60 min
- [ ] #5 Smoke 0-happy-install and 0-happy-upgrade run on the LXD box and leave the checkpoints the fault checks and arcs fork from
- [ ] #6 LXD guests are ubuntu:26.04
- [ ] #7 No release gate boots a Hetzner VM
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Owner direction 2026-09-28 18:56: move smoke AND the upgrade arcs to LXD; smoke creates the checkpoint images the fault checks and the arcs fork from. Design and measurements: tmp/lxd-all-gates.md. Guests move to ubuntu:26.04 (VM harness default). The 40 GB real-disk install leaves with smoke (owner's 07:21 ruling named this revisit condition); remaining coverage is Go tests. Parity: LXD verdicts match Hetzner at the same candidate (rc.16 arcs run 36468921894).

Plan review 2026-09-28 (Fable 5.1, one pass; Astra stopped on the OpenAI limit): SOUND WITH CHANGES, tmp/review-lxd-all-gates-plan.md. Revised milestones adopted: M2' smoke on LXD with provenance keys (user.statbus.candidate/producer/run_id), checkpoint-pending→checkpoint rename as smoke's last act, rerun-safe replace, per-job active marker vs reaper, single ramp job; M3a arc-aware LXD backend (tag-less install_statbus_at_sha, statbus-arc-* mapping, executable ssh/scp shim for 'timeout ssh', ProxyJump for deploy-status-proof, bounded volume for un-park-to-completion, GITHUB_TOKEN, ControlMaster), verified by hand on 4 hardest arcs incl. c-rollback reproducing rc.16's red; M3b arc workflow shadow run beside Hetzner; M4 orchestrator (construct at start, smoke always dispatched, box slot semaphore) + gates + delete Hetzner steps; M5 parity (every Hetzner red is an LXD red for the same reason). Estimate ~77 min on ccx33 sequential faults→arcs; ~40 min on a bigger box (423).

2026-09-29 05:42: M1 + M2' + M3a merged to master (a83039410) after 4 Opus 5.5 review rounds (tmp/review-lxd-m2*.md; round 4 APPROVE + R4-1/R4-2 landed 0aaafeb52). Live evidence: both smoke legs green on the box against rc.16; fault fleet on the branch backend 24/24 against rc.17 (matching master's rc.17 LXD run 36506437069); harden-host completed live. From the next RC, smoke (rungs 4/5) and the fault fleet (rung 7) run on LXD; upgrade arcs (rung 8) stay on Hetzner until M3b (shadow run beside Hetzner) and M4 (orchestrator + gates + delete Hetzner steps). Low follow-ups: harden-host refusal wording conflates SSH-probe failure with activity; PATH ssh shim intercepts local git-over-SSH when an operator runs run-forks.sh; H2 residue (upgrade-leg rerun after a failed -pre build refuses); M6 checkpoint name length at vX.Y.10.

Audit after v2026.09.3 (2026-09-29): Not in v2026.09.3. M1/M2'/M3a merged to master afterwards (a83039410). Harness Selftest red on master since (lxd-smoke-checkpoint-test, run 36534648749). Fix before the next candidate.

2026-09-29 13:15 UTC: M3b full-suite comparison run completed (worker session, ci/lxd-arcs worktree). run-arcs.sh v2026.09.3-rc.17, no --arc filter, LXD_PARALLEL=6: 35/35 arcs executed, wall time 1h12m49s (11:48:42Z-13:01:31Z, includes ~19min lost to a genuine Docker Hub infra timeout, not harness/product). Box left clean after.

Result: 30/35 confirmed green-parity against Hetzner rc.17 run 36509925405 (all 35 real-arc jobs). 5 reds:
- c-rollback-resurrection: mechanism-not-bytes comparison (this session's own R1 fix landed mid-run; the deterministic-epoch check itself was already proven rc.16-red/rc.17-green in a PRIOR session's isolated verification, documented earlier in tmp/lxd-all-gates-progress.md - not yet re-verified end-to-end in a full run after today's hang-bug fixes).
- postswap-health-park: confirmed pure infra (Docker Hub 502 on an unrelated image pull), not harness/product.
- restore-broke-reattempt, rollback-pair-terminal: UNRESOLVED, same failure shape ("expected terminal state, got superseded" on a PreSwap pair-terminal / STATBUS-228 check), never occurs on Hetzner. Needs root-cause work.
- worker-wedge-mid-derive: UNRESOLVED, "0 abandoned processing rows" - plausible LXD-vs-VM timing-fidelity gap (matches the original plan review's section-3 warning about CPU/timing differences), not yet root-caused.

Also found and fixed 4 real harness concurrency/correctness bugs live (none caught by any prior offline test), on top of landing round-R1/R2/R3 from rabbit's M3a review: (1) PINNED_ROOT git race across overlapping run-arcs.sh invocations, silently producing B==C on the crollback lineage - fixed with an mkdir-based cross-process lock; (2) arc_wait_unit_active's R1 timestamp comparison hung indefinitely on its first real run (psql_scalar's whitespace-stripping broke the ::timestamptz cast) - fixed via epoch-seconds + remote date -d, no more SQL string round-trips; (3) working-arc.sh's non-standard PASS-line prefix read as FAIL_NO_PASS_LINE despite genuinely passing - fixed to the standard prefix; (4, found by a parallel sibling session in the same worktree) capture_db_fingerprint's fixed-label scratch file collided across concurrently-running arcs - scoped on VM_NAME.

Full comparison table, per-arc notes, and the exact run/log paths are in tmp/lxd-all-gates-progress.md (2026-09-29T10:13-13:14Z entry). 45 commits total on ci/lxd-arcs, all G-signed, none pushed, none of the 6 previously-reviewed M3a commits rewritten.

Explicit gaps for the next session: root-cause the 2 unresolved "superseded not failed" reds and the worker-wedge timing red; re-verify c-rollback-resurrection end-to-end post-fix; copy the comparison TSV into a durable repo location (not only gitignored tmp/) per rabbit's parity-evidence instruction - not done this session, time-boxed out.

2026-09-29 15:15 UTC: M3b reds investigated. The final result is 33/35 verdicts matching Hetzner 36509925405, not complete identical-byte parity. Evidence is committed on ci/lxd-arcs at test/install-recovery/lxd/evidence/v2026.09.3-rc.17/ (d26b35449), with a 35-row final-comparison.tsv and a README.
- worker-wedge-mid-derive, a timing class: the arc released the lock before Postgres noticed the SIGKILLed worker's client (client_connection_check_interval 5s). The derive then completed. Hetzner passed only through slower SSH. Fixed in 7edb2f275 to hold the lock until an abandoned row is observed. PASS on LXD.
- rollback-pair-terminal and restore-broke-reattempt are a product behaviour that LXD exposes, not a harness bug.
  - A=ebe058af has since been promoted to v2026.09.3. On LXD the daemon's tag discovery works: A's row becomes release_status='release', and after the PreSwap rollback (HEAD=A) the 4th install's runInstallSupersede supersedes B's 'failed' commit row. This is proven by a ledger dump (c128ea335).
  - Independent review correction: 21 failed tag fetches were captured in eight Hetzner jobs, not every VM. The two disputed arcs have no daemon journal/discovery output in 36509925405 or rerun 36578946172/artifacts. An unchanged 'commit' classification for A in those two arcs is inferred, not directly captured. cross-version-rename-handoff recorded successful discovery.
  - The coordinator decides the disposition. It was not filed by this worker.
  - A related LXD fidelity bug was fixed along the way (8a57d5b5a: the candidate base had been installed through the historical-release path).
- c-rollback-resurrection with the final R1 code: rc.16 RED (db .Created 31s after rolled_back_at), rc.17 GREEN.
- postswap-health-park: infra, green on retest. working: green after 83b3b3b84.
- The commits on ci/lxd-arcs are G-signed and unpushed. The box is clean (s2-base checkpoints only).

2026-09-30 independent-review follow-through (tmp/review-425-m3b.md, MERGE WITH CHANGES):
- C1: arc_wait_unit_active still bypasses its deadline when the old invocation stays active or timestamps cannot be parsed. A bounded stub probe reproduced a hang; a worker is implementing deadline checks on every path and behavioral regression tests. Driver timeout, signal cleanup and stale construct-lock handling are also being corrected before re-review.
- C2: final TSV 'match=yes' means verdict agreement only. c-rollback-resurrection, worker-wedge-mid-derive and working compare final LXD arc bytes to the reference's pre-change bytes. Existing reference 36509925405 has 42 listed jobs, 41 executed and one skipped zero-arc guard. Corrected README/TSV committed as c2415e19f on ci/lxd-arcs after independent Opus MERGE (tmp/review-evidence-and-430-final.md); raw runs and observed verdicts are unchanged.
- C3(a), known fidelity work for M4/M5: the candidate base is now recorded by SHA, but historical LXD bases still take a release-install path (v2026.07.0-rc.05 and v2026.09.0) while Hetzner's two-argument path records 730b5001 and d53731ec. Align metadata identities or explicitly justify the retained difference before claiming full fidelity; the supersede procedure ranks that metadata.
- C3(b): STATBUS-435 now requires controlled or asserted discovery/enrichment in the two disputed arcs so live GitHub success or failure cannot choose the expected terminal state on either backend.
- Correct chronology: A=ebe058af was stable by about 07:14 UTC on 29 September, before synthetic untagged B=29986056 was created at 14:40:27. At 14:49:52, older installed stable-classified A superseded newer failed B by the tier-first rule. The earlier 'later promotion' narrative and blanket product-bug ruling were premature. Contract decision remains with the owner; procedure and assertions are unchanged.
- All acceptance criteria remain unchecked until their actual CI/live workflow evidence exists. No RC or release has been cut by this follow-through.

2026-09-30 14:45 UTC, local review follow-through:
- Lifecycle B1 is corrected in signed `8941353c5` and independently MERGE-able as code. Root's actual macOS Bash 3.2 tests pass. Linux execution remains unrun.
- Independent M4 review (`tmp/review-425-m4.md`) is frozen at exact refs. Original `db5f9387e` was BLOCK: the shared runner lost status 125 and released a still-owned admission slot, the default-domain fixture lacked the newly sourced marker helper, and ordinary arcs did not reuse smoke's installed checkpoint. `24dd9c237` and `5f789a6d9` resolve the first two with independent behavioral observations.
- Signed `83065bb80` selects the literal smoke-installed checkpoint for all 33 ordinary candidate-A arcs; the two historical bases retain exact full-SHA checkpoints. Independent Opus recheck resolves this requirement at code level. Fake-LXD checks are synthetic. Real guest boot, shallow-history B/C fetch, environment/certificate preparation and concurrent capacity remain unverified.
- At `dd384a382`, trap-less cancellation leaked its marker/slot after reaping its fork (R4), and non-atomic historical-A builder registration stranded a half-built checkpoint without an owner key (R5). Independent recheck of signed `b0b36dbd5` resolves R4/R5 and kills all five reviewer mutants. It also establishes a new blocker R6: normal PASS/FAIL leaves a stale process-group file, so the always-step can signal an unrelated process group that has reused that id. A bounded new correction is commissioned. These are defects in new unmerged wiring, not released product regressions.
- F1 remains open: a finalize-test return of 1 at exact `83065bb80` is unexplained because the initial failing log was lost. Seven reviewer passes and five further author passes with complete retained logs do not establish its cause. No 'flaky' waiver is taken. Signed `cfd3d61f8` removes the test's `ls | grep` warning and is independently MERGE-able as a test-only change, without changing the branch's BLOCK verdict.
- Root's isolated exact `dd384a382` combined finalize test passed in 54.4 seconds, preserving B1 no-signal-to-reaped-PID and live-owned-group status-125 behavior. This is macOS execution with host collaborators substituted, not real Linux/LXD/GitHub acceptance.
- According to the read-only control-plane/reaper investigation in `tmp/demo-installer-repair-proof-20260930.md`, the shared facility was reaped on 2026-09-29 at 18:36:23 UTC (run 36613191241), including its local checkpoints. That host-deletion receipt is attributed to the investigation, not the M4 code reviewer. Restoration approval is pending. No replacement host was provisioned, no code pushed and no candidate cut or promoted in this follow-through.
- Literal smoke reuse preserves A's tagged-install release classification. The STATBUS-435 disagreements are expected by mechanism on this literal path but have not been observed on it in a guest. Historical M3b disagreements were observed under the earlier documented fixture conditions. No SQL, release classification or arc assertion was rewritten to manufacture parity. Main's corrected chronology and preserved raw evidence remain authoritative.

Requirement mappings to settle before completion, without changing AC text or checkboxes:
- AC#1 says one CI job, while M4 retains per-arc matrix jobs on the shared host. Those names are the verifier's per-scenario marks and drive covered-subset inheritance.
- AC#2 calls for verdicts against a same-commit Hetzner run. The existing rc.17 reference is available, but new per-scenario Hetzner provisioning is forbidden; future-reference coverage cannot be assumed or created by violating that direction.
- AC#3's historic '4/4' wording no longer describes the concurrent '3/4' orchestrator grouping.
- AC#4 wall time is unmeasured on this wired path.
- AC#5 installed-smoke reuse is wired and code-reviewed, but guest-UNRUN.
- AC#7 literally says 'No release gate boots a Hetzner VM'. The shared LXD facility is itself a Hetzner ccx33 created on demand. Interpreting this as no per-scenario VMs is a requirement-mapping decision, not a verified literal fact.

Validation references: `tmp/review-425-m4.md`, `tmp/test-lxd-m4-dd384-finalize-20260930.log`, and `tmp/lxd-m4-implementation-20260930.md` in main's diagnostic directory. All seven acceptance checkboxes remain open.

2026-09-30 15:14 UTC, independent review Addendum 4:
- R6 is resolved at signed `daa91056909c83791e7fa4d6112d6910fe26e188`: normal PASS/FAIL drops the process-group file, while status 125 retains cleanup ownership. Actual helper/reap tests pass, both reviewer removal mutants are killed, and the harness selftest passes. R4/R5 remain resolved. This is local code/regression evidence, not a guest or GitHub outcome.
- F1 has a reproduced mechanism and remains a required code fix. The reviewer corrected the author's hook, which had intercepted the outer test's TERM and killed the driver before finalize ran. Against exact `83065bb80`, the corrected hook produces exactly the dead-PID safety failure with the other 24 checks passing, including exit 143, no surviving owned processes, and marker/fixture release. The no-hook control passes. The original failing log is unrecoverable, so identity with that event is not proven.
- The actual defect is a check-then-signal race: a selected raw PID can be reaped and possibly reused before TERM/KILL. A new signed correction is commissioned to signal and wait through the shell's current jobspec table, preserving the safety assertion and adding the corrected deterministic green-fix/red-revert regression. The branch remains BLOCK pending that independent recheck and external acceptance. No SQL, release classification or acceptance assertion changed; all seven acceptance checkboxes remain open.
<!-- SECTION:NOTES:END -->
