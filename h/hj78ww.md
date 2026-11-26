---
id: hj78ww
title: "Getting-started uploads go straight from the browser to /rest"
state: todo
type: feature
priority: ""
assignee: []
labels: []
group: ""
rank: "zzzzzzzzzzzv"
created: 2026-11-26
updated: 2026-11-26
---

## Goal
Each getting-started upload is one CSV POST from the browser to /rest, and the uploadFile server action is deleted.

## Purpose
Owner 2026-11-26: simpler and easier to debug: the request a page makes is the one an integrator makes, visible in the browser's network inspector, with no server in between that cannot be seen through.

## Principle
The browser talks to PostgREST directly; /api only for server-side work (bulk COPY, webhooks). The page's check and the error wording move to the browser; nothing about the views changes.

## Details
Pages: regions, sectors, legal forms, activity categories, custom units. Today app/src/app/getting-started/upload-csv-form.tsx calls uploadFile in getting-started-server-actions.ts, which strips a byte-order mark (prepareUpload) and translates PostgREST errors (explainUploadFailure, viewColumnsFromOpenApi) before a fetchWithAuth POST. Both helpers are plain functions and can run in the browser; fetchWithAuthRefresh is the browser fetch. Prefer: tx=rollback is enabled (1e34ef668) if a dry run helps.

## Depends on

## Acceptance
- [ ] Each getting-started upload page sends POST /rest/<view> with Content-Type text/csv from the browser, seen in the network inspector in Firefox
- [ ] A file with a bad row shows the same plain error as before, checked in Firefox on one upload page
- [ ] uploadFile and its server-only code are deleted; tsc, lint, jest and build pass

## Notes
