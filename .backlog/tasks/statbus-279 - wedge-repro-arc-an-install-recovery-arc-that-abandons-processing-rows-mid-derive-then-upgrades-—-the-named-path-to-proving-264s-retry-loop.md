---
id: STATBUS-279
title: >-
  wedge-repro-arc: an install-recovery arc that abandons processing rows
  mid-derive then upgrades — the named path to proving 264's retry loop
status: To Do
assignee: []
created_date: '2026-08-27 16:12'
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
Architect's ruling (2026-08-27): STATBUS-271 records STATBUS-264's retry loop as UNPROVEN, and an unproven guard needs a NAMED PATH TO PROOF, not a backlog entry — this ticket is that path. Deliberately NOT part of STATBUS-267 (a detector and a reproduction are different deliverables; bundling makes the detector wait on a VM arc).

The arc, reproducing the Norway wedge's two ingredients: on a VM, start derive work and stop the worker MID-DERIVE (leaving rows in 'processing'), then run the next upgrade so the worker restarts inside the read-only window. Against current binaries (264+265 aboard) the arc PASSES — 265's exemption means the reset is never refused, the wedge cannot form; it is a REGRESSION arc.

THE REQUIREMENT THAT DECIDES WHETHER IT IS EVIDENCE AT ALL: it must be demonstrated to FAIL against a pre-265 binary at least once (e.g. rc.09), or its green proves nothing — the RED rule applied to an arc.

WHAT IS ACHIEVED: the wedge class has a permanent regression arc, and 264's retry-then-FATAL has real-run proof instead of a recorded gap.
<!-- SECTION:DESCRIPTION:END -->
