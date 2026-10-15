---
id: STATBUS-370
title: Prove the harness failure path without a VM
status: Done
assignee: []
created_date: '2026-09-15 07:48'
updated_date: '2026-10-15 13:05'
labels:
  - testing
  - harness
  - fail-fast
dependencies: []
priority: high
type: task
ordinal: 10
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
### North Star
When a scenario fails, everything the box knows reaches the job log before the box is destroyed, and the harness proves this about itself without a VM.

### Zoom out
Failure paths run only when something is already wrong, late in a paid run. Untested, they lose the evidence they exist to keep. In the 2026-09-14/15 batch, four of six harness defects were in failure paths, each costing a run that taught nothing.

### Zoom in
- **Layer 1, static:** every started process registers its log; every lib function a scenario calls is defined.
- **Layer 2, stub box:** a localhost sshd drives the real harness library through its seams. Asserts the timeout diagnostic (exit code, last 30 lines), byte-identical registered-log capture, capture before delete, and `KEEP_VM=1` keeping the box. A built-in mutation of the real capture step must turn it red.
- **Layer 3, real host:** the failure capture observed on a real run.
- **Out of scope:** renaming proofs (STATBUS-359), ladder speed.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 ./dev.sh test-harness runs the stub-box contract green on the laptop with no network beyond localhost
- [x] #2 Harness Selftest runs on every master push and relevant PR, is green at the release commit, and release check consults it
- [x] #3 Negative proof: a mutation of the real capture step turns the contract red, inside the test itself
- [x] #4 test/install-recovery/README.md states that no scenario or harness change merges without its failure branch covered
- [x] #5 The failure capture is observed on a real host (LXD fleet, which replaced Hetzner gating per STATBUS-425)
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
### Evidence
- **AC1:** `./dev.sh test-harness` runs layers 1 and 2 (`test/install-recovery/tests/harness-failure-path-selftest.sh`).
- **AC2:** `.github/workflows/harness-selftest.yaml` green at rc.04 `3b17af171` (run `38729929511`); `release check` consults it (`WorkflowHarnessSelftest`, `cli/internal/release/workflow_check.go`).
- **AC3:** the self-test mutates the real capture `scp` and requires the contract to go red, on every run.
- **AC4:** `test/install-recovery/README.md` line 341ff.
- **AC5:** reinterpreted. The original asked for one Hetzner run; gating moved to the LXD fleet (STATBUS-425). Real rc.01–rc.03 failures produced on-runner captures, and those exposed truncation and a missing daemon journal, fixed in `4c88d3509`, `436c6ba2e`, `6f7ecb2ea`.

### Closing review
- **Memory:** none needed.
- **Documentation:** none needed; the README states the rule.
- **Cleanup:** the original hand-written design prose below the structured sections was removed; it remains in Git history (last present at `030704cd9`).
<!-- SECTION:NOTES:END -->
