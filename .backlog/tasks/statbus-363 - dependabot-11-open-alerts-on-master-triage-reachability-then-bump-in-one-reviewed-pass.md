---
id: STATBUS-363
title: >-
  dependabot: 11 open alerts on master (9 high): triage reachability, then bump
  in one reviewed pass
status: Done
assignee: []
created_date: '2026-09-07 19:46'
updated_date: '2026-09-23 15:10'
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

## Reconciliation 2026-09-23

Classification: PARTIAL. Evidence: dependency work is not on master; current app/package changes are uncommitted and alerts require retriage.

Remaining: Land reviewed dependency updates, complete next/sharp/Highcharts retriage, reach zero justified alerts, and pass CI/image smoke.

## Local implementation 2026-09-23 (STATBUS-363)

All 17 alerts currently open on GitHub were retriaged. All are npm alerts in
`app/pnpm-lock.yaml`; no Go module alert exists. The changes below are committed
locally only, so GitHub will continue to report the alerts until the commit is
pushed and Dependabot refreshes the dependency graph.

| Alert(s) | Outcome | Reachability and local fix |
|---|---|---|
| #680, #681 `next` | fixed locally | Runtime and reachable: the shipped Next server exposes the Image Optimization API and the app imports `next/image` in five source components/pages. Raised `next` from `^16.2.11` to `^16.3.3`; lockfile resolved 16.3.6, above the 16.3.3 fix. |
| #644, #679 `sharp` | fixed locally | Runtime and reachable through Next image optimization. Raised direct `sharp` from `^0.35.0` to `^0.35.4`; Next 16.3.6 also resolves sharp 0.35.4 instead of 0.34.5. |
| #626, #642, #669, #670, #682, #683 `js-yaml` | fixed locally | Dev/build-time only through Jest coverage and ESLint. Overrides resolve 3.x to 3.15.2 and 4.x to 4.3.2. |
| #640, #656, #657 `brace-expansion` | fixed locally | Dev/build-time only through glob/minimatch tooling. Override resolves 5.0.12, above the 5.0.9 fix. |
| #676, #677 `browserslist` | fixed locally | Dev/build-time compatibility tooling. Override resolves 4.29.0, above the 4.28.7 fix. |
| #678 `baseline-browser-mapping` | fixed locally | Dev/build-time browser compatibility data. Override resolves 2.11.20, above the 2.11.0 fix. |
| #609 `@babel/core` | fixed locally | Dev/build-time compiler/test tooling. Override resolves 7.29.7, above the 7.29.6 fix. |

Validation: `pnpm install`, 5 Jest suites/33 tests, TypeScript, lint (0 errors,
5 warnings), production build, and `pnpm audit` all passed. `pnpm audit` reports
zero vulnerabilities across 1002 dependencies. A built-server request to
`/_next/image` returned HTTP 200 for an auth-exempt public image path. No Go
gate was required because no Go files or Go dependencies changed. Full evidence
is in `tmp/statbus-363.md`.

## Resolution 2026-09-23

Status: **Done**. Commit `ff0003dfa` is on `origin/master`. It raises Next to
`^16.3.3` and sharp to `^0.35.4`, resolves the retriaged transitive alerts, and
records passing dependency install, 33 Jest tests, typecheck, lint, production
build, `pnpm audit` with zero vulnerabilities, and a `/_next/image` HTTP 200
smoke.
