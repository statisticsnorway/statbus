---
id: mzqz6f
title: "Two saves on one Save came from the agent browser tool, not StatBus"
state: "dropped"
type: feature
priority: ""
assignee: ["rabbit"]
labels: []
group: ""
rank: "zzzzzzzzzzzv"
created: 2026-11-26
updated: 2026-11-26
model: "claude-opus-5-5"
branch: "master"
worktree: "/Users/jhf/ssb/statbus"
dropped_reason: "not a defect: the agent browser tool's click fires twice; a real click and a real double-click each save once"
dropped_at: "2026-11-27T00:05"
---

## Goal
A Save on a unit's field sends one write, so one change runs one derive cycle.

## Purpose
The two POSTs at 22:49 came from the agent's browser tool, whose click fires two click events; the owner did not click. A real click saves once.

## Principle
Diagnose before fixing: the second submit came from the agent browser tool, so StatBus's save path stays as it is.

## Details
Playwright (tmp/mzqz6f-double-save.mjs): single click and double-click, insert and update paths, one server action and one REST write each. Page-world capture listener: one tool click on Cancel recorded two synthetic clicks. Reported to the jcode maintainer.

## Depends on

## Acceptance
- [ ] One Save click on a classification field sends one server action and one REST write (observed in the proxy log)
- [ ] A test fails before the fix and passes after it

## Notes


Diagnosis 2026-11-26 23:05: not a StatBus defect. The two writes came from the agent browser tool, whose click fires two synthetic click events (capture listener on Cancel recorded BUTTON:false twice for one call). Playwright real clicks, single and double-click, insert and update paths: exactly one server action and one REST write each (tmp/mzqz6f-double-save.mjs, tmp/journal.md). The owner never clicked; I did.
## History
- 2026-11-27T00:01 todo -> doing/active (take)
- 2026-11-27T00:05 doing/active -> dropped (drop); was doing_since: 2026-11-27T00:01
