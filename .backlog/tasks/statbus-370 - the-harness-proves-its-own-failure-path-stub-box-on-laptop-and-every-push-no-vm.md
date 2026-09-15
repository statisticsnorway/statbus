---
id: STATBUS-370
title: >-
  the harness proves its own failure path: every diagnostic, capture and keep branch is exercised on a stub box, on the laptop and on every push, with no VM
status: In Progress
assignee: []
created_date: '2026-09-15 07:48'
updated_date: '2026-09-15 07:48'
labels:
  - testing
  - harness
  - fail-fast
dependencies: []
priority: high
type: task
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

### Layer 2: stub box, the substance of this ticket
The harness reaches the VM through exactly these seams:
`SSH_OPTS` (vm-bootstrap.sh:100), `_hcloud_server_ip` (:179),
`_wait_for_ssh` (:244), `VM_EXEC` (:979), `scp`/`ssh` in the launchers and in
`capture_failure_artifacts` (:1809), `cleanup_vm` (:1953), and 36 `hcloud`
calls. A **stub box** is a real sshd the harness talks to over the same
seams: a local user (`statbus-stub`) with an authorized key, or a
throwaway container running sshd, chosen so the GitHub runner and a laptop
both have it in under a minute. `_hcloud_server_ip` returns `127.0.0.1`
(or the container ip); `hcloud` is a shim on PATH that records calls
(`server create/delete/list`) and never reaches Hetzner. The box has
`statbus` and `root`-equivalent users, `tmux`, `docker` shimmed to a
recorder.

On that box the suite PLANTS a state and FORCES a branch, then asserts the
observable contract. One test per branch, named for the claim:

| test | plants | forces | asserts |
|---|---|---|---|
| `stall-timeout-prints-first-install-diagnostic` | `/tmp/install-c10-first.log` (40 lines), `.exit`=`70` | stall never engages (no migrate process) | job log contains `exit 70` and the last 30 lines, verbatim; `MIGRATE_PID` is empty, not trap text |
| `err-trap-never-leaks-into-substitution` | a lib call that returns 1 inside `$( )` | | the variable is empty; the trap line is on stderr only |
| `failure-capture-copies-every-registered-log` | manifest with 3 entries, one missing | scenario rc=1 | `tmp/<vm>/registered/` has the 2 present files byte-identical, the index names the missing one as missing, sizes printed |
| `failure-capture-includes-standard-set` | fake compose/journal shims that emit known text | scenario rc=1 | compose ps, per-service logs, journal, `~/statbus/tmp/*.log`, marker json all present with the known text |
| `keep-vm-env-and-flag-skip-reap` | | `KEEP_VM=1` env; `--keep-vm` flag | `hcloud server delete` was NOT called (shim record); the job log says the VM was kept and how to reach it |
| `reap-happens-after-capture` | | scenario rc=1, no keep | shim record order: capture scp calls precede `server delete` |
| `success-path-does-not-capture` | | scenario rc=0 | no `tmp/<vm>/` directory, no capture banner |
| `config-copy-failure-is-loud` | `/tmp/env-config` unreadable to statbus | fresh wrapper | job log has the `harness: cannot copy` line with the `ls -l`; exit 70 |
| `umask-guard-refuses-only-other-read-stripped` | | wrapper under umask 0002, 0022, 0027, 0077 | first two proceed, last two exit 70 with the message |
| `admission-refusal-always-says-why` | parent JSON: completed / wrong sha / wrong path; tag fetch returning "would clobber" | admit.sh | every refusal prints its `::error title=` line; the clobber is a `::warning` and admission proceeds |

The scenario under test is not a product install: each test runs the
harness lib functions and, where a whole scenario is needed, a
`scenarios/`-shaped fixture under `tests/fixtures/` that exercises the
launch/wait/diagnose/cleanup shape without a product.

Negative proof, required: a test that reintroduces one of the four defects
above (e.g. re-adds `tee /dev/stderr` inside the substitution in a fixture
copy) and asserts the corresponding test goes RED. A suite that cannot fail
proves nothing.

### Layer 3: one real VM, on change only
The same assertions on a real CX23 with a fixture scenario that fails on
purpose, run when the failure machinery changes (not per candidate),
~€0.01. Recorded in this ticket with the run URL.

## Where it runs
- Laptop: `./dev.sh test-harness` (new verb; runs layers 1 and 2; brings up
  the stub sshd itself; no Hetzner, no Docker for the product).
- GitHub: a job in `fast-tests.yaml` or its own `harness-selftest.yaml` on
  every push to master and every PR touching `test/install-recovery/**`,
  `ops/setup-ubuntu-lts-24.sh`, `install.sh`, `.github/actions/**`. Free
  runner, ~2 min. Red blocks `release check` like any other workflow
  (add it to the prerelease gate table).

## Done when
- `./dev.sh test-harness` runs all layer-2 tests green on the laptop in
  under 3 minutes with no network beyond localhost.
- The GitHub job exists, is green at HEAD, and is consulted by
  `release check`.
- Each of the four defects above, reintroduced on a branch, turns the suite
  red (four negative runs recorded here with URLs).
- One layer-3 VM run recorded.
- Rule written into `test/install-recovery/README.md`: no scenario or lib
  change merges without its failure branch covered here.

## Not this ticket
Renaming the proofs (STATBUS-359). Making the ladder faster.
