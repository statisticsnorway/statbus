---
id: STATBUS-370
title: >-
  the harness proves its own failure path: every diagnostic, capture and keep
  branch is exercised on a stub box, on the laptop and on every push, with no VM
status: In Progress
assignee: []
created_date: '2026-09-15 07:48'
updated_date: '2026-09-23 15:10'
labels:
  - testing
  - harness
  - fail-fast
dependencies: []
priority: high
type: task
ordinal: 10
---

## Why

The install-recovery harness learns everything about a VM over SSH and then
destroys the VM. Every fact must leave the box through a failure path: an
ERR trap, an `|| { echo ...; }` block, a `set +e` fence, a capture-before-
reap step. Those paths run only when something is already wrong, on a paid
VM, an hour in, and nothing tested them. In the 2026-09-14/15 batch, four of
six harness defects were in failure paths, and each cost a VM run to learn
nothing:

| defect | commit | what it hid |
|---|---|---|
| `git fetch --tags --quiet` under `set -e` in admit.sh | `4284eeca2` | three RCs refused with no message |
| `cp ... 2>/dev/null \|\| true` on the one config copy | `df6727be4` fixed | released binary said "no config" |
| `$(ls -l ... 2>&1)` exits 2 under `set -e` inside the diagnostic | `d888ea443` fixed | the message meant to explain never printed |
| `tee /dev/stderr` inside `$( )` + lib ERR trap; `run.sh` resets `KEEP_VM` | `586ebf4d2` fixed | ERR text became `MIGRATE_PID`, timeout branch skipped, VM reaped with the log on it (two paid runs) |

Principle (owner, 2026-09-15): on the happy path the harness proves the
product; on the failure path the harness must prove ITSELF. A failure path
is a contract, and contracts get tested, cheaply, before any VM is paid for.

## Design

Three layers. The first two need no VM and run on every push.

### Layer 1: static (exists since 2026-09-15)
- `tests/process-log-registration-test.sh`: every process the harness starts
  on a box registers its log in the manifest.
- `tests/…declare -F…` (rose, `518831ff7`): every lib function a scenario or
  arc calls is defined.

### Layer 2: one test, the substance of this ticket

The contract, in one sentence: **when a scenario fails on a box, everything
the box knows arrives in the job log before the box dies.**

One test proves it. A stub box is a real sshd on localhost reached through
the harness's own seams (`SSH_OPTS`, `VM_EXEC`, `_hcloud_server_ip` ->
127.0.0.1, `hcloud` shimmed to a recorder). A fixture scenario, shaped like a
real one, launches one process via `_run_long_via_tmux` that writes a known
40-line log, then fails with rc=1 at a `wait_for_...` timeout. Assert, on
the harness's own stdout/stderr and `tmp/<vm>/`:

1. the timeout branch printed the process's exit code and its last 30 lines,
   verbatim (so a human can act without a rerun);
2. `capture_failure_artifacts` copied the registered log byte-identical into
   `tmp/<vm>/registered/` and printed the index with sizes;
3. the `hcloud server delete` call in the shim record comes AFTER the last
   scp, and does not happen at all under `KEEP_VM=1` (run the fixture twice).

Negative proof, required: reintroduce one of this batch's failure-path
defects in a copy of the fixture (the `tee /dev/stderr` inside `$( )`) and
the test goes red. A test that cannot fail proves nothing.

Admission, umask and config-copy already have their own tests; they are not
this test. Add clauses here only when a NEW way of losing evidence is found.

### Layer 3: one real VM, on change only
The same assertions on a real CX23 with a fixture scenario that fails on
purpose, run when the failure machinery changes (not per candidate),
~€0.01. Recorded in this ticket with the run URL.

## Where it runs
- Laptop: `./dev.sh test-harness` (new verb; runs layers 1 and 2; brings up
  the stub sshd itself; no Hetzner, no Docker for the product).
- GitHub: a job in `fast-tests.yaml` or its own `harness-selftest.yaml` on
  every push to master and every PR touching `test/install-recovery/**`,
  `ops/setup-ubuntu-lts.sh`, `install.sh`, `.github/actions/**`. Free
  runner, ~2 min. Red blocks `release check` like any other workflow
  (add it to the prerelease gate table).

## Done when
- `./dev.sh test-harness` runs the layer-2 test green on the laptop in
  under 2 minutes with no network beyond localhost.
- The GitHub job exists, is green at HEAD, and is consulted by
  `release check`.
- The negative proof is recorded here (one red run with URL).
- One layer-3 VM run recorded.
- Rule written into `test/install-recovery/README.md`: no scenario or lib
  change merges without its failure branch covered here.

## Not this ticket
Renaming the proofs (STATBUS-359). Making the ladder faster.

## Batch sequencing (owner ruling 2026-09-15)

This ticket lands in the ONE batch after the current release: it does not
touch master until v2026.09.1-rc.08 (or the first later rc that goes fully
green) has been installed on Norway and promoted to stable. Then all batch
tickets land in one push, one candidate, one ladder. Position in that push:
**1 of 8**. harness self-test on a stub box; lands first so the batch ladder itself is protected by it

Batch order: 370 -> 368 -> 367 -> 363 -> 357 -> 361 -> 362 -> 359.

## Update 2026-09-22

The requested layer-2 stub-box contract is not present on master. Current tests
cover individual cleanup, process-log registration, partial-allocation, and
concurrent-install observation paths, but there is no `./dev.sh test-harness`
verb, no localhost sshd stub-box test that proves capture-before-delete and
`KEEP_VM=1` ordering, and no recorded negative mutation proof or layer-3 VM run.
Status remains **In Progress**.

## Reconciliation 2026-09-23

Classification: PARTIAL. Evidence: scratch harness self-test only; not on master and not exercised on every push.

Remaining: Land the laptop/every-push failure-path harness and its mutation controls.

## Implementation 2026-09-23

Added `./dev.sh test-harness` and a localhost-sshd self-test that runs both the
delete and `KEEP_VM=1` paths. It verifies the 30-line timeout diagnostic, a
byte-identical registered-log copy, the printed size index, and scp-before-delete
ordering. A mutation control reintroduces the historical `tee /dev/stderr`
inside command substitution and verifies that the test rejects it. The new
`Harness Selftest` workflow runs on every master push and relevant pull request,
and `release check` consults it as a commit-scope workflow gate.

Local proof is recorded with the implementation commit. The workflow's green
run and the layer-3 paid VM proof can only be recorded after the commit is pushed
and included in the next candidate harness run, respectively. Status remains
**In Progress** until those external proofs exist.
