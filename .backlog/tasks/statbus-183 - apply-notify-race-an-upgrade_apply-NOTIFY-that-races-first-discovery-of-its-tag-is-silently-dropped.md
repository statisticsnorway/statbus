---
id: STATBUS-183
title: >-
  apply-notify-race: an upgrade_apply NOTIFY that races first discovery of its
  tag is silently dropped
status: To Do
assignee: []
created_date: '2026-07-14 16:12'
labels:
  - upgrade
  - deploy
  - fail-fast
  - defect
dependencies: []
priority: medium
ordinal: 184000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
> NORTH STAR: a delivered apply poke either schedules the named version or fails LOUDLY — never a silent no-op that leaves the row available and the operator believing the deploy is in flight.
> FOUND: 2026-07-14 ~18:00, rc.06 canary on rune (live box, read-only diagnosis). deploy-via-upgrade run 29347796677 delivered `NOTIFY upgrade_apply, 'v2026.07.0-rc.06'` and exited green. Journal: the daemon DISCOVERED the tag at 18:00:31 (signature verified, "Discovered: v2026.07.0-rc.06"), verified + pre-downloaded all images by 18:02:07 — and then nothing. 25+ minutes later the row (id 42843) sat state='available', scheduled_at NULL, docker_images_status=ready, release_builds_status=ready, not parked, daemon unit active. The apply was dropped: the NOTIFY arrived while the tag was not yet a registered candidate (the release was ~4 minutes old; the poke raced the box's own first discovery of it), and whatever the handler did between "trigger discovery" and "schedule the named version," the scheduling half never happened — with zero error surfaced anywhere.
> CONTRAST: the rc.05 poke on the same box (same workflow, same shape) went row-completed in 78 seconds — the tag had been discoverable longer. Timing is the only visible difference.
> REMEDY USED: a second identical poke (run 29348619144) — the row then existed registered with images ready. The canonical operator retry works; the silence is the defect.
> RELATION: the STATBUS-170 arc one level deeper — 169 fixed green-means-scheduled lies, 170 makes green mean converged; this is "even the poke can be lost silently." 170's phase-2 polling would have caught this in CI (timeout → red naming 'available'), which is evidence for its priority, but the product should not drop a delivered apply either way.
> COMPLEXITY: engineer trace first (find the exact drop site in the apply handler: does it resolve the tag BEFORE its own check completes? does an error get swallowed?), then architect rules the fix (make apply wait-for/trigger registration then schedule, or fail loudly to the poke's output).
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Engineer traces the exact drop site in the upgrade_apply NOTIFY handler with file:line (why discovery ran but scheduling didn't, and where the error went)
- [ ] #2 Architect rules the fix shape: apply always either schedules the named version (registering it first if needed) or fails loudly
- [ ] #3 Fix proven by a run: a poke sent within seconds of a fresh release schedules correctly (or fails loudly) — no silent available-forever row
<!-- AC:END -->
