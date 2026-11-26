---
id: zamdqe
title: "Unit pages use the width they need, not always the full screen"
state: "doing"
type: feature
priority: ""
assignee: ["rabbit"]
labels: []
group: ""
rank: "zzzzzzzzzzzu"
created: 2026-11-26
updated: 2026-11-26
stage: "active"
model: "claude-opus-5-5"
branch: "master"
worktree: "/Users/jhf/ssb/statbus"
doing_since: "2026-11-26T11:38"
doing_with: "ca6dk5"
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
- [x] On a wide screen the unit Contact page keeps a readable width and the address parts sit in one row, approved by the owner in a browser

## Notes


2026-11-26 10:38 rabbit takes over from ladybug (stopped: one directory per agent); its uncommitted edits in ~/ssb/statbus are the starting point.
check 1: Owner approved in Firefox 2026-11-26 13:13 on the local slot (Norway copy): forms and Links at max-w-6xl with address parts in one row; History wide for its table; chart width by observations (1 obs 360 px, 8 obs ~544 px). Committed 37a8812b4 (local).
Pushed to master 2026-11-26 18:25 (1c49640e0 / 37a8812b4).
landed 37a8812 on master 2026-11-26: app: unit pages take the width their content needs; the history chart grows with…
## History
- 2026-11-26T11:05 todo -> doing/active (take)
- 2026-11-26T11:38 doing/active -> todo/ready (give back; was assignee: ladybug); was doing_since: 2026-11-26T11:05
- 2026-11-26T11:38 todo/ready -> doing/active (take with ca6dk5)
