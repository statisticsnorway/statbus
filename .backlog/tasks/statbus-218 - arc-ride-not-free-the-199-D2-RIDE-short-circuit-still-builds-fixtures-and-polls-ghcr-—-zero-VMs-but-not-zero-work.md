---
id: STATBUS-218
title: >-
  arc-ride-not-free: the RIDE shortcut skips the VMs but still spends 20-30
  minutes building images it will not use
status: To Do
assignee: []
created_date: '2026-08-17 21:46'
updated_date: '2026-08-18 07:41'
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
> NORTH STAR: a cost shortcut should skip the cost. RIDE today skips only the most expensive slice of it.

FOUND: 2026-08-17 by the architect during the STATBUS-215 review. Cost and latency only — no correctness impact, and the ratified RIDE behaviour (a legitimate green skip) is unchanged.

WHAT HAPPENS: when a tag push contains no upgrade-relevant changes, the run "rides" — no arcs are selected, no Hetzner VM ever boots, so the workflow's "0 VMs" claim is accurate. But the two preparation jobs (construct and image-wait in .github/workflows/upgrade-arc-harness.yaml) carry no skip condition, so a riding run still pushes its throwaway test/* fixture branches, kicks off an image build for each, and polls the registry until every image exists — about 20-30 minutes for a cold build. Then teardown deletes the branches nothing used.

THE COST: a GitHub runner held for that whole window, a full set of throwaway image builds — and, worse, the shared hetzner-vm-fleet queue slot held the entire time, delaying install-recovery-harness and test-install behind a run that will execute nothing.

THE FIX, WITH A WARNING FROM 215: give construct and image-wait the same skip decision run-arc effectively has. But making construct skippable puts a skipped job into every downstream needs chain — the exact implicit-success() trap STATBUS-215 just fixed — so every downstream `if:` must be re-audited for that class, teardown must stay always-on, and teardown must tolerate branches that were never created.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 A RIDE run skips construct and image-wait (no fixture branches pushed, no images.yaml dispatch, no ghcr poll) while still concluding green
- [ ] #2 Every downstream job's `if:` is re-audited against the STATBUS-215 implicit-success() poisoning class once construct becomes skippable
- [ ] #3 teardown still runs and succeeds when no fixture branches were ever created
- [ ] #4 A non-RIDE tag push and a workflow_dispatch both still run the full construct → image-wait → run-arc chain unchanged
<!-- AC:END -->
