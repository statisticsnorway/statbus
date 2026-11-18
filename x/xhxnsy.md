---
id: xhxnsy
title: "Workflows: an analysis produces an import job to review and apply"
state: todo
type: feature
priority: ""
assignee: []
labels: []
group: ""
rank: "zy"
created: 2026-11-18
updated: 2026-11-18
---

## Goal
StatBus has a Workflows page where batch changes are made through the import system: a built-in workflow analyses a chosen frame, produces an import job with its proposed changes, and the user previews, approves and applies it like any import.

## Purpose
Batch corrections (unit size, primary units) should be made with the same preview, review, approval and accountability as imports, not as silent updates (owner 2026-11-18). This is how people are meant to do bulk work in StatBus.

## Principle
Workflows are built in (hard-coded), not user-written. Each can be activated or not on the Workflows page. A run is: pick an active workflow, configure it (frame, variable), run it, get an import job with the changes, review, apply. Nothing changes the data except the import job. Long-term task; first workflows are unit size and primary selection.

## Relevant details
Flow from the owner, 2026-11-18: Workflows page lists the workflows and which are active; the user picks an active one, goes through it, configures it, runs it; the result is an import job with the changes, which can be reviewed and applied. Reuses the existing import system throughout (preview, approval, look at data). Related: the data-quality check in xz3jej finds legal units whose primary establishment has another activity; a workflow could later propose the fix.

## Depends on

## Acceptance
- [ ] [Owner] Designs the Workflows page and the workflow contract (what a workflow takes as configuration, what import definition its job uses) in a session; the answer is recorded in the notes and becomes the build plan
- [ ] A Workflows page lists the built-in workflows and lets an administrator activate or deactivate each
- [ ] Running an active workflow on a chosen frame creates an import job whose rows are the proposed changes, shown in the existing import review before anything is applied
- [ ] Applying that job changes the data exactly as an import of the same rows would, with the edit recorded as made by the user who applied it

## Notes

2026-11-18 14:54 the first workflow to build is 2gpcs7 (pick the primary unit by a variable); its result feeds the quality check xz3jej (on master 8aaf0262b, in the next release candidate). PR #328 closed with this explanation: https://github.com/statisticsnorway/statbus/pull/328
