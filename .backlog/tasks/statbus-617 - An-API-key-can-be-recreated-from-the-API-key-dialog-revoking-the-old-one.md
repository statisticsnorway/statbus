---
id: STATBUS-617
title: An API key can be recreated from the API key dialog, revoking the old one
status: In Progress
assignee: []
created_date: '2026-11-11T12:40:00Z'
updated_date: '2026-11-11T13:26:00Z'
labels:
  - app
  - auth
dependencies: []
priority: medium
ordinal: 530204
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
## North Star
A user who has exposed an API key replaces it in one step, where they already find it, and the old key stops working at once.

## Zoom out
2026-11-11: PR 324 (Erik Søberg) committed his admin_user API key for ma.statbus.org to a public branch. Rotating it today is possible only over REST (rpc/login, rpc/create_api_key, rpc/revoke_api_key), which we wrote out for him in the PR (comment 6796072544). Proven locally: tmp/pr324-rotation-local.log (old key 200, after revoke 'API Key has been revoked.', new key 200).
The app's only API key UI is the command palette's 'Show API key' dialog (app/src/components/command-palette/api-key-dialog.tsx). It shows the first key and copies it, nothing else.

## Zoom in
Owner 12:39: a Recreate (refresh) button on the show-key dialog. Recreate creates a new key (same description and duration) and revokes the one shown, then shows the new token to copy.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 The API key dialog offers Recreate; pressing it shows a new token, and the previous token is refused with 'API Key has been revoked.'; a test asserts both against the REST API
- [x] #2 The dialog shows the active key (not a revoked one) when the user has several keys; a test asserts it
- [ ] #3 [Owner] Recreates his key on a box after the release carrying this. The answer is recorded in this ticket's notes: yes closes the ticket; no gives the error to investigate.
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
2026-11-11 owner asked for it in rc.02 (12:50). Built eee0bc661: lib/api-key.ts recreateApiKey (create_api_key with the same description and lifetime, then revoke_api_key on the shown jti; the old key stays if creation fails); the dialog shows the newest unrevoked key and a 'Recreate key' button. Test api-key.test.ts RED tmp/617-red.log, GREEN tmp/617-green.log; jest 270, tsc 0, lint 0 errors. Real app (tmp/617-recreate-check.mjs/.json): after Recreate the old token is refused (400 'API Key has been revoked.') and the new one works (200). AC#3 waits for the owner on a box after the release.

Dialog shows the newest active key: description, Name in key (with a line that course certificates show it and a /profile link), created, valid until with days left, active count; a red warning when the profile name differs from the name in the key. Recreate key asks in an AlertDialog first. Commits eee0bc661 (recreateApiKey), 2f12f1705 (details + confirm), c0f614959 (name in key + warning), cb60a4146 (name line). Real app: tmp/617-recreate-check.json (Cancel keeps the key; confirm recreates; old token refused 400, new token 200), tmp/617-name-check.json. Owner approved the dialog in Firefox 2026-11-11 13:19. On master in 379e738d9.
<!-- SECTION:NOTES:END -->
