---
id: STATBUS-363
title: >-
  dependabot: 11 open alerts on master (9 high): triage reachability, then bump in one reviewed pass
status: In Progress
assignee: []
created_date: '2026-09-07 19:46'
updated_date: '2026-09-07 20:05'
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

## Triage result (2026-09-07 20:05, `tmp/dependabot-triage.md`)

All 11 alerts are npm, all in `app/pnpm-lock.yaml`, all transitive. No Go, no Actions. No major-version jumps anywhere.

| reachability | alerts | action |
|---|---|---|
| exploitable here | sharp 0.34.5 (GHSA-f88m-g3jw-g9cj), pulled in by `next@16.2.11`; `next/image` is used in 6 source files and loads sharp at runtime | `pnpm.overrides` `sharp: ^0.35.0` (the direct dep is already ^0.35.0). Own commit, own image-optimization smoke before an RC |
| dev/build-time only | browserslist x2, js-yaml x4, brace-expansion x3, @babel/core | one `app/` commit: overrides/`pnpm up`, then `tsc && lint && build && test` |

Not in the current batch RC. The sharp override touches the production image path, so it goes into the release after, with its own smoke.

## Next

Step 2 (bump) unassigned until the batch RC is cut. Then: one builder, one adversarial reviewer, sharp separate from the rest.
