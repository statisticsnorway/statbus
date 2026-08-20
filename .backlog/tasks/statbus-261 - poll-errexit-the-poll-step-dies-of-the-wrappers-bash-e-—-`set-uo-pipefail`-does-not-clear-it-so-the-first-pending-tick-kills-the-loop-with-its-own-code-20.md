---
id: STATBUS-261
title: >-
  poll-errexit: the poll step dies of the wrapper's bash -e — `set -uo pipefail`
  does not clear it, so the first "pending" tick kills the loop with its own
  code 20
status: To Do
assignee: []
created_date: '2026-08-20 06:35'
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
