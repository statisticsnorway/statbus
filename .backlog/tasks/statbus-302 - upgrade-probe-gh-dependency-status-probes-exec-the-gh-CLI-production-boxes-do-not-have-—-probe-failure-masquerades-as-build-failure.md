---
id: STATBUS-302
title: >-
  upgrade-probe-gh-dependency: status probes exec the gh CLI production boxes do
  not have — probe failure masquerades as build failure
status: In Progress
assignee:
  - '@architect'
created_date: '2026-08-28 16:24'
updated_date: '2026-08-28 21:28'
labels:
  - upgrade
  - cli
  - ops
dependencies: []
priority: high
type: bug
ordinal: 295000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
NORTH STAR: an NSO box must be able to report a candidate's build status using only what the product installs. Today the upgrade service's status probes shell out to the `gh` CLI — which production boxes do not have — so candidates show "images failed" / stuck "artifacts building" for reasons that are about the PROBE, not the images.

THE EVIDENCE (King's screenshots, 2026-08-28): demo.statbus.org and a second (unidentified) slot both show the verbatim error 'CI images absent after 20m0s timeout; gh probe err=exec: "gh": executable file not found in $PATH' against candidates whose images may be perfectly fine. VERIFIED IN CURRENT CODE, not just old binaries: service.go:1722 and :4322 run `gh api repos/.../actions/workflows/...` — the dependency is live at master.

WHY IT IS WRONG: (a) gh is not installed by ops/setup-ubuntu-lts-24.sh and never will be on an NSO box — the probe fails everywhere production runs; (b) even where gh exists, an unauthenticated fallback hits the shared-IP 60/hr quota (the 287/rate-limit family); (c) the failure is misattributed to the CANDIDATE ("CI image build failed") when it is the probe that could not run — a false verdict shown to an operator.

FIX SHAPE (architect to rule): the probes must use what the product already has — plain HTTPS. The release manifest is already fetched tokenlessly (FetchManifest); the image-existence question can be answered by a ghcr.io manifest HEAD (tokenless for public images) instead of asking GitHub Actions' API how the workflow felt. Where workflow-conclusion truly matters, the probe must degrade honestly: "could not determine build status (no gh CLI)" — never "images failed". Distinguish probe-failure from build-failure in both the row status and the UI text.

WHAT IS ACHIEVED: a candidate's status on an NSO box reflects the candidate, not the probe's toolchain; and no operator is told a build failed when nobody could check.
<!-- SECTION:DESCRIPTION:END -->

## Comments

<!-- COMMENTS:BEGIN -->
author: architect
created: 2026-08-28 21:28
---
**RULING: the fix direction is right. Adopt it — but SPLIT it, because only one half is cheap enough for this round.**

## What this actually is

`service.go:1722` and `:4322` shell out to `gh api`. On a production box `gh` does not exist, so the probe cannot run — **and its inability to look is being reported as a finding about the thing it failed to look at.** "Could not check whether the build exists" is being rendered as "the build failed."

That is the third instance of one defect class this week (the straggler guard swallowing `docker compose exec`'s exit; `CompareVersions` answering for inputs it documents as unorderable; this). **A failure to observe is not evidence about the observed.**

## THREE states, and the two directions must fail OPPOSITE ways

The probe must report **BUILT / NOT BUILT / COULD NOT DETERMINE**, and the third is not a flavour of the second.

- **ACTING fails closed:** on COULD NOT DETERMINE, do **not** schedule an upgrade whose artifacts are unverified. Unverified is not permission.
- **REPORTING fails honest:** never render it as "build failed". Say the check could not run, and why (`gh` absent / network refused / HTTP status).

**Those two directions are deliberately opposite**, and collapsing them is exactly today's bug: the current code refuses to proceed *and* tells the operator the release is broken. One of those is right.

## SPLIT — ride rc.17 with the first half only

**HALF A, rides rc.17 (cheap, self-contained):** replace both `gh api` execs with the tokenless HTTPS path — `FetchManifest` already exists at `github.go:171`, and a ghcr manifest HEAD answers image existence. Add the honest third outcome in the **message text** and in the act/report asymmetry above. **This removes the false "build failed" from every production box and needs no schema change.**

**HALF B, next round:** carrying COULD NOT DETERMINE distinctly in the **row status and UI**. If that needs a status value and a migration plus frontend text, it is not a same-day change and must not be squeezed into a round whose purpose is cheap validation — **and a half-built status model is worse than none, because a third state that dies at the storage boundary reads as the second.**

Half A is the one that matters operationally: it stops the lie. Half B makes the truth structured.

## Staffing

**Mechanic for Half A** — two call sites, one existing helper, message text. **If it turns out the third outcome cannot be expressed without touching the row status, stop and report rather than inventing a status value**; that is Half B and it is the engineer's.

**Verify before building:** confirm the ghcr manifest HEAD is genuinely tokenless for this package's visibility. The whole half rests on that, and it is one `curl -I` to settle.
---
<!-- COMMENTS:END -->
