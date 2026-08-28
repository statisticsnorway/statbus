---
id: STATBUS-279
title: >-
  wedge-repro-arc: an install-recovery arc that abandons processing rows
  mid-derive then upgrades — the named path to proving 264's retry loop
status: In Progress
assignee:
  - '@engineer'
created_date: '2026-08-27 16:12'
updated_date: '2026-08-28 09:56'
labels:
  - testing
  - upgrade
  - worker
dependencies: []
priority: medium
type: task
ordinal: 272000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
NORTH STAR: STATBUS-264's retry-then-FATAL guard is recorded UNPROVEN on the release ticket (271) — no normal upgrade exercises it, because 265's exemption means the reset is never refused on any healthy path. An unproven guard needs a named path to proof, not a standing note. This arc is that path.

THE ARC, reproducing the Norway wedge's two ingredients on a real VM: (1) start derive work and stop the worker MID-DERIVE, leaving rows in 'processing' — the abandoned state the wedge was made of; (2) run the next upgrade, so the worker restarts inside the upgrade's read-only window and meets those rows. Against current binaries (264+265 both aboard since rc.10) the arc PASSES — 265's exemption means the reset is never refused and the wedge cannot form. It joins the fleet as a permanent REGRESSION arc (test/install-recovery/arcs/, one scenario in the upgrade-arc-harness matrix).

THE REQUIREMENT THAT DECIDES WHETHER IT IS EVIDENCE AT ALL (the RED rule applied to an arc): the arc must be demonstrated to FAIL at least once against a pre-265 binary (e.g. rc.09) before its green counts. A regression arc that has never been seen red proves only that it runs, not that it guards — the same vacuous-green class as a test pin that passes with the bug present.

DELIBERATELY SEPARATE from STATBUS-267 (the stuck-task detector): a detector and a reproduction are different deliverables, and bundling would make the detector wait on VM-arc work.

SEQUENCING: not release-blocking — 264+265 are aboard every candidate since rc.10 and the proving sequence does not wait on this. It queues behind the stable promotion; building it costs one arc scenario plus one deliberate red run against an old binary (paid Hetzner VM time, same as any arc).

WHAT IS ACHIEVED: the wedge class has a permanent regression arc that has been seen red, and 264's retry-then-FATAL has real-run proof instead of a recorded gap.
<!-- SECTION:DESCRIPTION:END -->
