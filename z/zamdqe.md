---
id: zamdqe
title: "Unit pages use the width they need, not always the full screen"
state: "doing"
type: feature
priority: ""
assignee: ["ladybug"]
labels: []
group: ""
rank: "zzzzzzzzzzzz"
created: 2026-11-26
updated: 2026-11-26
doing_since: "2026-11-26T11:05"
stage: "active"
model: "claude-opus-5-5"
branch: "master"
worktree: "/Users/jhf/ssb/statbus"
---

## Goal
Unit detail pages grow with their content up to a sensible maximum, so wide screens show no stretched forms.

## Purpose
Owner 2026-11-26: Hedda's full-width unit pages (dropped from the merge, commit 60e1d3243 on origin/ui/fixes-and-improvements) become too wide on a long screen.

## Principle
Use the whole screen where the content needs it (tables, address rows) and a max width where it does not.

## Details
Hedda's change: details-page-layout.tsx max-w removed, address parts in one row in contact-info-form.tsx (legal unit, establishment, enterprise).

## Depends on

## Acceptance
- [ ] On a wide screen the unit Contact page keeps a readable width and the address parts sit in one row, approved by the owner in a browser

## Notes


## History
- 2026-11-26T11:05 todo -> doing/active (take)
