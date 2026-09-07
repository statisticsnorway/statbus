---
id: STATBUS-363
title: >-
  dependabot: 11 open alerts on master (9 high): triage reachability, then bump in one reviewed pass
status: In Progress
assignee:
  - hare (deepseek-v4-pro, triage)
created_date: '2026-09-07 19:46'
updated_date: '2026-09-07 19:46'
labels:
  - security
  - dependencies
  - app
dependencies: []
priority: high
type: task
---

## Description

GitHub reports 11 open Dependabot alerts on `statisticsnorway/statbus` master
(9 high, 1 moderate, 1 low), surfaced on every push. Nobody has looked at them.
Presumed mostly frontend (`app/`), unverified.

## Work

1. **Triage (read-only, in progress).** One table, one row per alert: package,
   ecosystem, severity, GHSA, vulnerable range, patched version, manifest,
   direct/transitive, and reachability here: "exploitable here", "present but
   unreachable", or "dev/build-time only", each with a one-line reason.
   Output: `tmp/dependabot-triage.md`.
2. **Bump.** Group into the minimal set of upgrade actions. Major-version jumps
   are flagged and get a dedicated test pass; everything else lands in one
   commit per ecosystem (`app/pnpm-lock.yaml`, `cli/go.sum`, workflows).
3. **Verify.** `cd app && pnpm run tsc && pnpm run lint && pnpm run build &&
   pnpm run test`; `cd cli && go test ./...`; runner CI green at HEAD.
4. **Review.** Adversarial review of the diff by a different session before
   merge. Any alert left open must be dismissed in GitHub with the
   reachability reason from step 1, not ignored.

## Done when

`gh api repos/statisticsnorway/statbus/dependabot/alerts?state=open` returns
zero rows, or every remaining row is dismissed with a written reason that
matches the triage table. CI green at HEAD.

## Not in the batch RC

This is not part of the current batch candidate (035/339/337/341/354). It
lands after that RC unless triage finds something exploitable in the deployed
app, in which case the coordinator asks the owner.
