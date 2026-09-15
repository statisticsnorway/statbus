---
id: STATBUS-363
title: >-
  dependabot: 11 open alerts on master (9 high): triage reachability, then bump
  in one reviewed pass
status: In Progress
assignee: []
created_date: '2026-09-07 19:46'
updated_date: '2026-09-15 08:15'
labels:
  - security
  - dependencies
  - app
dependencies:
  - STATBUS-367
priority: high
type: task
ordinal: 40
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

## Step 2 built (kikazaru, 2026-09-14 12:58), held in scratch until rc.05 is cut

Scratch `$JCODE_SCRATCH_DIR/statbus-363`, branch `statbus-363`, commit
`ce9de0f65` (signed): `app/package.json` overrides only, lockfile regenerated,
sharp/next untouched. browserslist 4.28.1->4.28.9, js-yaml 3.14.2/4.3.0->
3.15.1/4.3.1, brace-expansion 5.0.6->5.0.9, @babel/core 7.28.6->7.29.7; no
major bumps. Alerts addressed: 677 676 670 669 642 626 657 656 640 609.
`pnpm install --frozen-lockfile`, tsc, lint (0 errors), build, test (28 pass)
all green. Open alerts on master now 17 (was 11 at triage; new ones arrived,
retriage after this lands). sharp 644 stays for its own commit + next/image smoke.

Next: Sol review of ce9de0f65, cherry-pick after the cut, then retriage the
six new alerts, then sharp.

## Review round 1 and fix (2026-09-14 13:26)

Sol (retriever) REJECT on one P1: alerts #682/#683 (published after the
triage) require js-yaml above 3.15.1/4.3.1. Fixed in `7e7b9186c` (js-yaml
3.15.2/4.3.2; baseline-browser-mapping resolves 2.11.20, closing #678);
gate reran green. Sol also classified the six alerts new since triage:
#678 addressed by regeneration; #679 sharp needs >= 0.35.4; **#680/#681
next, critical, need next >= 16.3.3** (Image Optimization API). So the
"sharp commit" is now a Next minor bump + sharp, with its own next/image
smoke, after rc.05. Retriage table in scratch `tmp/review.md`.

Pending: Sol round 2 on 7e7b9186c, cherry-pick after the cut, then the
next/sharp commit.

## Step 2 accepted (2026-09-14 13:29)

Sol round 2 ACCEPT on `7e7b9186c` (with `ce9de0f65`): no findings; frozen
install clean, tsc/lint/build/test green (28/28). Ready to cherry-pick onto
master after rc.05 is cut. Remaining: the Next >= 16.3.3 + sharp >= 0.35.4
commit with a next/image smoke, then retriage to zero.

## Batch sequencing (owner ruling 2026-09-15)

This ticket lands in the ONE batch after the current release: it does not
touch master until v2026.09.1-rc.08 (or the first later rc that goes fully
green) has been installed on Norway and promoted to stable. Then all batch
tickets land in one push, one candidate, one ladder. Position in that push:
**4 of 8**. dependabot: ten build-time bumps, Sol-accepted in scratch (ce9de0f65 + 7e7b9186c); the Next >= 16.3.3 + sharp commit with its next/image smoke is ALSO in this batch, built and reviewed before the push

Batch order: 370 -> 368 -> 367 -> 363 -> 357 -> 361 -> 362 -> 359.
