---
id: STATBUS-402
title: >-
  When the installer cannot proceed, the operator gets one plain reason, one fix
  and the exact rerun command
status: In Progress
assignee: []
created_date: '2026-09-24 15:35'
updated_date: '2026-10-15 19:11'
labels:
  - release-bug
  - install
  - error-handling
dependencies:
  - STATBUS-387
priority: high
type: bug
ordinal: 355000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
### North Star
When the installer cannot proceed, the operator reads one plain sentence saying what is wrong, one thing to do about it, and the exact command to run again. Nothing more is needed to recover.

### Zoom out
The installer stops for one of two kinds of reasons, and each has its own promise:
- **Refusal before any change** (exit 78): something outside StatBus is not ready (disk, Docker, a busy port, a restart still running). Nothing was changed, so the message is the reason, the outside fix and the rerun command. It is not a breakdown, so there is no alarming banner and no support bundle.
- **Failure after work began:** the message names the step, the cause and the fix, gives the rerun command, and points to the support file in case it stops at the same place again.

In both cases operator output is written for an operator. Implementation vocabulary (invariants, guards, locks, shell source, internal state names) stays in the install log, where support reads it. Only known, fixed sentences cross from the log to the terminal, so an arbitrary error text can never leak through. The rerun command repeats the operator's own invocation with the chosen version, channel and answer files (STATBUS-387).

### Zoom in
- **Incident, Finland 2026-09-24 (v2026.09.2):** a disk-space refusal before anything was installed printed `install.sh FAILED at line 716: ( exec < /dev/tty; ./sb install ...`, a `SYSTEM UNUSABLE` banner, `Invariant breached: (no named invariant ...)`, a support bundle, and the advice `STATBUS_MIN_DISK_GB=85 ./sb install`, which failed from the home directory (`-bash: ./sb: No such file or directory`) (`tmp/finland-transcript-actual.txt:14-38`).
- **Shipped:** `add66cae9` (v2026.09.3) keeps internal diagnostics in the log and simplifies operator failures. `28c07da3e` routes named refusals back to the operator. `install.sh` handles exit 78 with an allowlist of full-line-anchored remedies (port in use, disk, Docker absent/stopped/denied, restart running, state undetermined, certificate settings), each ending with the exact saved rerun command. After work begins, `printInstallStepFailure` (`cli/cmd/install.go`) emits `INSTALL_CAUSE` / `INSTALL_FIX`, which `install.sh` prints as `Cause:` / `Outside fix:` / the rerun command / `send this file to StatBus support: <bundle>`.
- **Proof today (2026-10-15):** `test/install-recovery/tests/fresh-installer-test.sh` passes locally, 20 cases including `no-TTY piped install prints exact remedy without catastrophic banner`, `port, disk, and restart remedies reach operator without internal diagnostics`, `classified step cause and outside fix reach wrapper without raw errors` and `rerun retains version, flags and absolute quoted answer paths`. Go: `TestInstallOperatorOutputContainsNoInternalDiagnostics`, `TestInstallFailureCauseOperatorTextContainsNoInternalDiagnostics`, `TestEveryInstallerRerunHintUsesSavedCommand`, `TestRerunCommandPreservesInvocationOptions`, all green.
- **Real box:** `4-install-port-80-taken.sh` shows a real refusal naming `sudo systemctl disable --now apache2`, then a healthy rerun with the saved answers.

### Closing review
- **Memory:** none needed.
- **Documentation:** none needed; the messages are the documentation.
- **Cleanup:** none.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 A preflight refusal exits 78 and prints the plain reason, one outside fix and the saved rerun command, with no breakdown banner or support bundle (`fresh-installer-test.sh`: no-TTY, port, disk, restart cases)
- [x] #2 A failure after work began prints the step, cause, outside fix, rerun command and support-file path with a non-78 exit (`fresh-installer-test.sh`: classified cause and database-route cases)
- [x] #3 Operator-facing output contains no implementation vocabulary while the install log keeps the traces (`TestInstallOperatorOutputContainsNoInternalDiagnostics`, `TestInstallFailureCauseOperatorTextContainsNoInternalDiagnostics`)
- [ ] #4 Owner decision: do the wrapper and Go tests plus the real-box port-80 refusal close this, or is one real-box post-start failure scenario required? The answer closes the ticket or adds that scenario.
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
### Evidence
- **AC1-3:** green locally on master, 2026-10-15 (`tmp/vet/fresh-installer-test.log`).
- **Superseded criteria:** the 2026-09-24 restyle pointed at two test files that were never written (`installer-post-start-failure-output-test.sh`, `installer-output-vocabulary-test.sh`) and an exit-78 case it said `harness-failure-path-selftest.sh` lacked. The coverage landed in `fresh-installer-test.sh` and the Go tests above instead.
<!-- SECTION:NOTES:END -->


## Release gate observation 2026-09-25

**Merged follow-up, proof pending.** rc.02 (`2198185bb`) failed the concurrent-install refusal ([run 36104217764, job 107973800359](https://github.com/statisticsnorway/statbus/actions/runs/36104217764/job/107973800359)). `8689926a4` names the live installation instead of an upgrade; `ddd3f6408` includes diagnostic PID; `47173a31d` stamps PID and start time across six install-held marker writers and routes refusals through `LiveInstallHolderRefusal` (`cli/internal/upgrade/service.go:1705-1717`, `cli/cmd/install.go:383`). Flock alone establishes liveness. The rc.03 VM refusal is still unobserved, and this does not complete AC #1-3.

v2026.09.3 rc.02 failed `1-boot-concurrent-install` in [Actions run 36104217764, job 107973800359](https://github.com/statisticsnorway/statbus/actions/runs/36104217764/job/107973800359): a second installer correctly refused an install-held live mutex, but printed `An upgrade is already running` instead of naming the installation. The flag already records `holder=install` and `started_at`; it did not retain the process ID. Review follow-up records the install holder's PID as diagnostic-only metadata (the flock remains the sole liveness proof), renders it alongside start time in plain operator wording, and removes the `lsof` hint. The concurrent-install VM scenario now requires that the diagnostic PID equal the flag PID and remains proof pending until rerun; this observation does not complete AC #1-3.

Second review caught the other install-held marker writers: restart claim and preparation, operator-start guard, and the flagless rollback / restore-reattempt authorization claims. All six production writers now stamp start time and PID; the live install, restart, start-guard, and fresh-claim refusals use one plain PID-bearing line. A stale flag's PID is never treated as liveness. An AST audit guards every production writer, and focused tests exercise each holder kind; VM proof remains pending.

Baseline: `origin/master` at `373d15fc3`. Criterion disposition and remaining positive targets are above; the acceptance criteria below remain authoritative. An authored but unrun VM scenario is **proof pending**, not met.
