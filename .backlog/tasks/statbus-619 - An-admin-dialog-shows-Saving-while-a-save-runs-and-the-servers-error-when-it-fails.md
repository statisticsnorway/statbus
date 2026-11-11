---
id: STATBUS-619
title: >-
  An admin dialog shows Saving… while a save runs and the server's error when it
  fails
status: In Progress
assignee: []
created_date: '2026-11-11T12:43:00Z'
updated_date: '2026-11-11T14:18:00Z'
labels:
  - app
  - db
  - admin
dependencies: []
priority: high
ordinal: 532204
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
## North Star
An administrator who saves in an admin dialog sees at once that the save is under way, cannot press Save twice, and sees why a save failed.

## Zoom out
Erik (Slack 2026-11-11 13:38 local): on no.statbus.org, disabling a statistical variable (turnover) 'does not work'; on demo it does. Read-only findings on Norway (rune, v2026.11.4-rc.01, 3.1M statistical units):
- The changes did land: stat_definition turnover enabled = false; external_ident_type stat_ident enabled = false.
- Each save took 8.6 to 13.3 s in the database (db log 12:35:09 to 12:36:28 GMT); Erik pressed Save several times.
- The admin dialog forms showed nothing while the server action ran: no pending state, the dialog stayed open until success, a failure was only in the debug panel.
The wait itself (the regeneration after a change) is STATBUS-620, split off by the owner at 12:48.

## Zoom in
One shared footer for the seven admin dialog forms (statistical variables, identifier types, data sources, statuses, unit sizes, activity category settings, users): app/src/app/admin/admin-dialog-footer.tsx. While useActionState is pending, Save and Cancel are disabled and Save reads 'Saving…' with a spinner; a failed save shows the server's message above the buttons.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Every admin dialog form shows Saving… with Save and Cancel disabled while the save runs; a test asserts the pending footer
- [x] #2 A failed save shows the server's message in the dialog; a test asserts it
- [x] #3 [Owner] Sees Saving… on a slow save in Firefox. The answer is recorded in this ticket's notes.
- [ ] #4 [Owner] Saves a statistical variable on Norway after the release carrying this and sees Saving… until it is done. The answer is recorded in this ticket's notes: yes closes the ticket; no gives the error to investigate.
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
2026-11-11 12:48 owner: split; this ticket is the Saving… state only, the regeneration in the worker is STATBUS-620. Built 5fe1d9118: AdminDialogFooter in all seven admin dialog forms. Test admin-dialog-footer.test.tsx RED tmp/619-footer-red.log (module missing), GREEN tmp/619-footer-green.log (3/3); jest 268/268, tsc 0, lint 0 errors. 12:51 owner saw the spinner in Firefox on a slow save (AC#3). AC#4 waits for the release carrying this (rc.02).

2026-11-11 14:05: in release candidate v2026.11.4-rc.02 (49376c40a; CI all green, ./sb release check green). Release tests held up by outside outages (Hetzner core limit, then Canonical snap store); re-run when the store answers. Remaining owner checks after the release reaches a box.
<!-- SECTION:NOTES:END -->
