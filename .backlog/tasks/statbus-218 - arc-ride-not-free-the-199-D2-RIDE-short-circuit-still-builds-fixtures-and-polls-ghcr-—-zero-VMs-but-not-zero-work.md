---
id: STATBUS-218
title: >-
  arc-ride-not-free: the RIDE shortcut skips the VMs but still spends 20-30
  minutes building images it will not use
status: To Do
assignee: []
created_date: '2026-08-17 21:46'
updated_date: '2026-08-18 07:43'
labels:
  - ci
  - release
dependencies: []
references:
  - .github/workflows/upgrade-arc-harness.yaml
priority: low
type: enhancement
ordinal: 218000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
WHAT THIS PART DOES: when a release tag contains no upgrade-relevant changes, the arc workflow deliberately "rides" — it selects zero test scenarios and finishes green, inheriting the previous release's proof instead of re-spending 31 VM boot-and-test cycles. A ratified cost shortcut (STATBUS-199 D2).

WHAT GOES WRONG: the shortcut only skips the final stage. The two preparation jobs still run in full, so a riding run spends 20-30 minutes preparing for tests it has already decided not to run. Found 2026-08-17 by the architect during the STATBUS-215 review; cost and latency only, no correctness impact.

THE DETAIL: construct and image-wait (.github/workflows/upgrade-arc-harness.yaml) carry no skip condition. A riding run therefore still pushes its throwaway test/* fixture branches, kicks off an image build for each, and polls the registry until every image exists — about 20-30 minutes cold. Then teardown deletes the branches nothing used. The bill: a GitHub runner held for the whole window, a full set of throwaway image builds, and — worst — the shared hetzner-vm-fleet queue slot held the entire time, delaying install-recovery-harness and test-install behind a run that will execute nothing.

THE FIX, with the STATBUS-215 lesson applied: give construct and image-wait the same ride decision run-arc effectively has. Care required — making construct skippable puts a skipped job into every downstream needs chain, which is exactly the implicit-success() trap 215 just fixed. So: re-audit every downstream `if:` for that class, keep teardown always-on, and make teardown tolerate branches that were never created.

WHY THAT HELPS: a riding run then costs nearly nothing and releases the fleet queue immediately. The shortcut delivers the saving it was designed for, and real test runs stop waiting behind empty ones.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 A RIDE run skips construct and image-wait (no fixture branches pushed, no images.yaml dispatch, no ghcr poll) while still concluding green
- [ ] #2 Every downstream job's `if:` is re-audited against the STATBUS-215 implicit-success() poisoning class once construct becomes skippable
- [ ] #3 teardown still runs and succeeds when no fixture branches were ever created
- [ ] #4 A non-RIDE tag push and a workflow_dispatch both still run the full construct → image-wait → run-arc chain unchanged
<!-- AC:END -->
