---
id: j2g6wd
title: "Lint every open task once hug stops linting done tasks"
state: todo
type: chore
priority: ""
assignee: []
labels: []
created: 2026-11-18
updated: 2026-11-18
---

## Goal
Every open task (todo or doing) on the StatBus board passes hug task lint, so the board's findings are all actionable.

## Purpose
Today hug lints done and dropped tasks too, and the old imported board makes hundreds of findings that hide the ones that matter (owner 2026-11-17 23:39). The owner is having hug changed so done tasks are not linted.

## Principle
Wait for the hug release that skips done tasks, then fix the open tasks one by one with the owner. Tasks another agent has taken are theirs to fix. Done tasks are left as they are.

## Relevant details
Installed now: hug v0.7.50 (brew veridit/tap/hug). Open tasks with findings on 2026-11-17: Rabbit's senzch, hmgadt, 00rnq5; the rest of the todo tasks were not yet counted. Check with: hug task lint (after the release, it covers only open tasks).

## Depends on

## Acceptance
- [ ] A hug release later than v0.7.50 is installed and hug task lint reports no done or dropped tasks
- [ ] hug task lint reports no findings on any open task, except tasks another agent has taken, which are named in the notes

## Notes
