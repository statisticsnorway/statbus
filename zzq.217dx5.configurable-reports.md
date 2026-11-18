---
id: 217dx5
title: "Configurable reports: an administrator chooses which checks the dashboard shows"
state: todo
type: feature
priority: ""
assignee: []
labels: []
created: 2026-11-18
updated: 2026-11-18
---

## Goal
An administrator chooses which of StatBus's built-in reports and data-quality checks appear on the dashboard, so each country sees the ones that matter to it.

## Purpose
As checks are added (missing region, missing activity, primary establishment activity in xz3jej, missing physical location), not every country wants every card (owner 2026-11-18).

## Principle
Only the built-in reports and checks are chosen here; adding new ones is a separate task. The choice is a setting stored in the database and changed in the admin pages, not a code or .env change. Every check stays reachable through the search even when its card is hidden.

## Relevant details
Today the Data quality section in app/src/app/dashboard/page.tsx hard-codes its cards (MissingRegionCard, MissingActivityCategoryCard). New cards in flight: the primary-establishment activity check (xz3jej) and Rabbit's missing physical location (89f3jm, on statbus-628-all-forms).

## Depends on

## Acceptance
- [ ] [Owner] Decides the shape: a list of every built-in report and check with an on/off switch (and whether order is configurable), where it lives in the admin pages, and the default for a new installation; the answer is recorded in the notes
- [ ] Turning a check off in the admin page removes its card from the dashboard for every user, and turning it on brings it back, without a restart (Jest test plus a check in Firefox)
- [ ] A check hidden from the dashboard is still reachable through its search link, and a new installation shows the agreed default set (Jest test)

## Notes
