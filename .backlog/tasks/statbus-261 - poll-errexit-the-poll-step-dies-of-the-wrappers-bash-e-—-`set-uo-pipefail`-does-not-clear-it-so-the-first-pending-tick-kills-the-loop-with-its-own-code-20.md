---
id: STATBUS-261
title: >-
  poll-errexit: the poll step dies of the wrapper's bash -e — `set -uo pipefail`
  does not clear it, so the first "pending" tick kills the loop with its own
  code 20
status: Done
assignee: []
created_date: '2026-08-20 06:35'
updated_date: '2026-08-20 06:50'
labels:
  - ci
  - release-chain
dependencies: []
references:
  - 'https://github.com/statisticsnorway/statbus/actions/runs/32339996885'
  - 'https://github.com/statisticsnorway/statbus/actions/runs/32338450700'
  - .github/workflows/deploy-to-dev.yaml
priority: high
type: bug
ordinal: 254000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
rc.09's chain run (the first END-TO-END exercise of STATBUS-260's fixed transport) proved the transport and then died of a one-line shell bug in the new poll step.

WHAT THE RUN PROVED FIRST, so the red is read correctly: the orchestrator dispatched deploy-to-dev with the candidate SHA explicitly (job 3/5), dev's byte-pinned ops/ci-deploy-status.sh EXISTS and ANSWERED (exit 20 = pending), and the stop-gate held — legs 4/5 and 5/5 (the fleets) were SKIPPED, nothing promoted. The 260 transport works.

THE BUG: deploy-to-dev.yaml's "Poll until the upgrade converges" step opens with `set -uo pipefail`, but GitHub wraps every run: step in `bash -e {0}`, and `set -uo` does NOT clear the wrapper's `-e`. Under errexit, `out="$(poll)"; rc=$?` is fatal the moment poll returns non-zero: the assignment itself fails and bash exits with that code before `rc=$?` or the case statement ever run. The first tick returned 20 — the exit contract's "pending, keep polling" — and the step died one second after starting, reporting "Process completed with exit code 20". The loop's own logic (0/10/20/30/64/127/255 handling, 20m budget) never executed even once.

Run evidence: run 32339996885, first poll 06:32:21Z, death 06:32:22Z, env REQUESTED_SHA=bba72a4a57d08b43f6bf983be2606f45c7fe3cf3.

FIX SHAPE (architect to ratify): make the step immune to the wrapper — `set +e` after the pipefail line (with a comment naming the wrapper's -e as the reason), or capture without a bare failing assignment (`rc=0; out="$(poll)" || rc=$?`). NOTE the rider in the yaml: the loop shape is DELIBERATELY duplicated across all 7 deploy-to-*.yaml; a loop-shape change lands 7× knowingly — but the other six are queued for deletion behind Wave D and nothing writes their deploy branches, so the architect should rule 1× vs 7×.

VERIFICATION: the run is the only oracle on chain yaml. After the fix lands on master, deploy-to-dev can be dispatched manually with the same candidate SHA to prove the poll leg against dev's real state; full zero-hands 246/247/249/252 evidence still requires the next cut's chain run (which is gated behind STATBUS-259's niue root session, or SKIP_SSHDOERS=1).

WHAT IS ACHIEVED: the chain's convergence verdict on dev actually comes from the poll loop's contract, not from whichever tick happens to return first.
<!-- SECTION:DESCRIPTION:END -->

## Comments

<!-- COMMENTS:BEGIN -->
author: foreman
created: 2026-08-20 06:38
---
DEV CONVERGED on rc.09 at ~06:39Z — the byte-pinned status read (same command CI runs) returned exit 0, `completed|false|`. So the box side of the whole 260 transport is PROVEN end to end: explicit dispatch → poke → named candidate resolved (DEPLOYED_COMMIT == REQUESTED_SHA) → installed → converged. The only broken link was the chain's poll, dead of the wrapper errexit one second in.

This also makes post-fix verification cheap: once the fix lands on master, dispatching deploy-to-dev with the SAME sha (bba72a4a57d08b43f6bf983be2606f45c7fe3cf3) should poke (idempotent — candidate already completed), poll a converged state, and go green in one tick — proving the loop's 0-arm against real state. The 10/20-arm behaviour is then proven by the next cut's live run.
---

author: engineer
created: 2026-08-20 06:43
---
**FIX BUILT AND FROZEN + AUDIT DONE.** One file changed: `.github/workflows/deploy-to-dev.yaml`. actionlint clean (only the pre-existing SC2088 on the deliberate `~`, shifted by added lines); Go pins for 259/260 still green.

## The fix, and the proof it works

Both capture sites now use `rc=0; out="$(…)" || rc=$?` — the poll (~309) and the poke (~155). The idiom rather than `set +e` for the ruled reason, written at the line: this poll's non-zero exits are a VOCABULARY (the 0/10/20/30/64 contract), so a command whose exit code is DATA gets captured deliberately, while `set +e` would declare that nothing in the step is checked and un-protect the ssh key install and trap above it.

**Proved under a real `bash -e` wrapper rather than argued.** Old shape: dies immediately, wrapper exit 20, the case statement never reached — exactly rc.09's symptom. New shape: reaches the case statement with rc=20 and exits 0. The poke's `[ "$rc" -eq 0 ] || loud-error` branch is now reachable, and its message carries the exit code.

## I CLAIMED A SECOND BUG AND TESTING DISPROVED ME

I read `[ -n "$out" ] && last="$out"` as a second landmine — an AND-list returning 1 when the poll output is empty, on precisely the transient-read path the loop exists to tolerate. I "fixed" it to an `if`, wrote a confident comment about it, and then tested it: **it does not die.** Bash exempts a failing command in an `&&` list unless it follows the final `&&`, so the assignment is skipped and execution continues.

I reverted the change and left the line exactly as it was, with a short note recording that it is safe and that the reasoning said otherwise. Shipping the "fix" would have been harmless; shipping the COMMENT would have put a confident false claim about bash semantics into a file people copy from.

## Both divergences stated in one comment, as ruled

The rider says a loop-shape change lands 7×. This file has now broken that symmetry twice — the poll subject (260) and the errexit capture (261) — and both are recorded together where the rider is, with the shared reason: those six are queued for deletion behind Wave D, nothing writes their deploy branches, their boxes are opt-in human. Their real fix is Wave D landing sooner. Without the note, someone restores consistency by reverting a fix.

## AUDIT — read-only, three fingerprint sites, no live bugs

**orchestrator :252 and :345 — SAFE.** Both open `set -uo pipefail` (the fingerprint) but each wraps its capture in an explicit `set +e` … `set -e`. The author knew.

**upgrade-arc-harness :910 — SAFE TODAY, FRAGILE.** Fingerprint present, no `set +e`, and a loop calling `delete_throwaway_branches` for seven specs before `exit 0`. It cannot die today because the helper `return 0`s unconditionally and swallows its own `git push --delete` failure (upgrade-target.sh:766-772). But the `exit 0` shows best-effort intent that errexit would contradict the moment the helper gains a failing path or the loop gains a command. Worth a comment; not worth a change.

**Everything else in both files is a safe form** — `|| true`, `if cmd; then`, `if ! cmd; then`. `$?` appears only at the two guarded orchestrator sites.

**The class's full extent, for the Wave D argument:** with comment lines excluded, five of the six condemned deploy-to-*.yaml still carry exactly one bare `out="$(…)"; rc=$?` each (et, jo, ma, tcc, ug) and none carries a guard. Untouched per the brief — recorded so the count is a fact rather than an impression.

One process note: my first sweep counted three bare captures in deploy-to-dev and two `set +e` — all of them inside my own comments quoting the broken form. Grep does not know prose from code, which is the same trap the STATBUS-224 parse-don't-grep convention exists for. The numbers above are with comment lines stripped.
---

author: foreman
created: 2026-08-20 06:46
---
LANDED at 8e0a24c69 (architect verdict: LAND, verified at source; actionlint clean in the throwaway worktree). Both sites captured with `rc=0; … || rc=$?`; both deliberate divergences recorded in one block at the rider; the engineer's self-disproved second-bug note stays (architect: recording that the question was asked and answered is exactly right).

RULINGS FOR LATER, pinned so they are not lost:
1. upgrade-arc-harness :910 — OUT of this unit (scope is one file), and "comment-only" is the wrong end-state: a comment at the caller documents a coupling instead of removing it. When the arc-harness's own unit comes: apply the same || rc=$? idiom at :910, and if any note is written the valuable half goes at the HELPER (upgrade-target.sh:766-772 — "callers rely on this returning 0 unconditionally"), the end where a breaking change would originate. Deferring is safe: it cannot die today, and a future helper failure surfaces as a loud teardown red.
2. WAVE D DATUM, framed as the argument it is: five of the six condemned deploy-to-*.yaml carry exactly one bare unguarded capture each (comment-stripped count) — five workflows that would die on their first non-zero tick if ever dispatched. A concrete reason to land Wave D's deletions sooner, not a patch backlog.

VERIFICATION NEXT (architect-ruled partial oracle): dispatch deploy-to-dev with the SAME sha (bba72a4a57d0…). Dev already converged, so a green proves the step no longer dies and the COMPLETED arm reads correctly; the PENDING loop — the code that died — stays UNPROVEN until the next cut's live run and is recorded as such.
---

author: foreman
created: 2026-08-20 06:50
---
VERIFICATION RUN GREEN — run 32341044889, dispatched with the same rc.09 candidate sha at master tip 9fc8bf33b (carrying the fix). Evidence from the log: apply-latest ran idempotently and emitted deployed_commit=bba72a4a5… == REQUESTED_SHA (guard equal); the poll's first tick read `completed|false|`, ENTERED THE CASE STATEMENT — the code errexit made unreachable — took the 0-arm, printed "deploy converged: completed|false|" and "GREEN — bba72a4a5… reached 'completed' on dev.", exited 0.

ARM ACCOUNTING, as the architect required: this proves the step survives a non-fatal capture and reads the COMPLETED arm correctly. The PENDING loop (repeated 20-ticks under budget) and the 10-arm remain UNPROVEN until the next cut's live chain run — recorded here so this green is never read as "the poll leg is proven". That proof rides the rc.10 chain.
---
<!-- COMMENTS:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
The rc.09 chain's red was one shell line: GitHub wraps every workflow step in bash -e, `set -uo pipefail` does not clear it, and `out="$(poll)"; rc=$?` died on the first pending tick with the poll's own code 20. Fixed at 8e0a24c69 with `rc=0; out="$(…)" || rc=$?` at both capture sites in deploy-to-dev.yaml (poll + poke, whose loud-error branch was dead the same way), the exit-code-as-data reasoning at the line, and both deliberate divergences from the six condemned copies recorded at the rider. Proved under a real bash -e wrapper before landing, then by dispatch run 32341044889: the poll entered its case statement and read dev's converged state correctly. Pending/10-arm proof deliberately recorded as riding the next cut. Audit: orchestrator sites guarded (safe), arc-harness :910 fragile-but-safe (idiom lands in its own unit, note at the helper), five of six condemned copies carry the same bug unguarded — an argument for Wave D landing sooner.
<!-- SECTION:FINAL_SUMMARY:END -->
