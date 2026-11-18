---
id: "9vpx9v"
title: >-
  config-apply-gap: every .env.config edit leaves file and behaviour disagreeing
  until someone regenerates and restarts — ./sb install should apply config
  changes
state: "todo"
assignee: []
labels:
  - cli
  - config
  - ops
group: ""
rank: "000000000377"
dependencies: []
priority: low
type: "feature"
origin: "backlog:STATBUS-331"
aliases: ["STATBUS-331"]
backlog_type: "enhancement"
created: "2026-08-31 14:53"
---

## Goal

NORTH STAR: an operator who edits .env.config has one obvious next command, and after it the box's behaviour matches its file. Today the gap between editing and effect (config generate + service restart) lives in the operator's memory — a box whose file and behaviour disagree is exactly the failure class STATBUS-307 exists to kill.

FILED FROM the architect's superseding CLI-verb ruling on STATBUS-307 (2026-08-31): the upgrade-channel verb is KEPT for now precisely because it carries this three-step workflow (write key, regenerate, restart) for one key. The gap is general, not channel-specific — every .env.config key has it. The right long-term home is ./sb install applying config changes as part of its idempotent config work (it already runs the step-table as a config refresh in the nothing-scheduled state); once install closes the gap for every key, the channel verb becomes redundant and can be removed for the reason originally given (the downstream unknown-value refusal covers every writer; a verb covers only its users).

EXPLICITLY NOT part of the 307 landing (architect: "must not be folded into this landing").

WHAT IS ACHIEVED: edit the file, run ./sb install, done — for every key; and one special-case verb retires.

## Acceptance
- [ ] #1 ./sb install (nothing-scheduled path) detects that generated outputs are stale relative to .env.config and regenerates + restarts what the change requires
- [ ] #2 The upgrade-channel verb is removed in the same landing, with a doc sweep
- [ ] #3 No second config-application mechanism: the step-table is the one home
