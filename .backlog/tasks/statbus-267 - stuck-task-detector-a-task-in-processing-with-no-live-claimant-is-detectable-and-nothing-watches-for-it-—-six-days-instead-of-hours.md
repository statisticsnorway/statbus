---
id: STATBUS-267
title: >-
  stuck-task-detector: a task in processing with no live claimant is detectable
  and nothing watches for it — six days instead of hours
status: To Do
assignee: []
created_date: '2026-08-27 12:49'
labels:
  - worker
dependencies: []
priority: medium
type: enhancement
ordinal: 260000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
From STATBUS-262: four tasks sat in 'processing' with no live claimant for six days on a box that looked healthy — the worker ran every other queue, the upgrade reported completed, and the wedge was found by the King in a progress bar. Worker-health was the wrong place to look, because the worker WAS healthy.

Architect's ruling: the wedge's signature is A TASK IN 'processing' WITH NO LIVE CLAIMANT for longer than any plausible runtime — detectable, cheap, and it would have surfaced this in hours. Build the detector as a loud guard (per the two-tier discipline: this is a warning surface, not a silent self-heal — detection reports loudly; any automatic remediation is a separate argued decision, see feedback rule "no standing self-heal paths").

Design questions for the architect at build time: where it runs (worker maintenance loop vs admin UI vs both), what "plausible runtime" means per command class, and how it reports (the admin worker-tasks UI already renders states — a stuck-processing badge there reaches the human who looks).

WHAT IS ACHIEVED: an orphaned processing task is a loud finding within hours, not a silent wedge found by a human staring at a frozen progress bar.
<!-- SECTION:DESCRIPTION:END -->
