---
id: STATBUS-338
title: >-
  preswap-fetch-resilience: skip/retry the redundant target fetch, nil-safe
  rollback, truthful error — the Norway rc.02 trio
status: Done
assignee: []
created_date: '2026-09-02 11:20'
updated_date: '2026-09-02 11:51'
labels:
  - upgrade
  - defect
  - resilience
dependencies: []
priority: high
type: bug
ordinal: 331000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Norway's rc.02 upgrade failed on a transient GitHub blip amplified by three product defects (full RCA: rune log tmp/upgrade-logs/43078-v2026.09.0-rc.02-20260902T102652Z.log, foreman-relayed 2026-09-02).

1. Redundant one-shot network fetch at the worst moment: preswap Step 6 runs `git fetch origin <sha>` AFTER maintenance mode + DB stop (cli/internal/upgrade/service.go:6631 via fetchWithStallDetection), though discovery already fetched the objects — they were local and signature-verified. KING'S RULING: this class of error is just a RETRY. Fix: verify objects locally (git cat-file) and skip the fetch when present (the normal case); when a fetch is genuinely needed, bounded transient retry, and hoist it BEFORE maintenance mode so a network failure never costs downtime.
2. Rollback panics on nil queryConn: executeUpgrade closes/nils the DB connection, rollback dereferences it (service.go:9586 area); Run's defers repanic (nil-unsafe). Fix: nil-safe rollback + defers, preserving the ORIGINAL error text end-to-end.
3. Misclassification: the restart recovery manufactured INSTALL_PRECONDITION_FAILED ('do NOT re-schedule') for what was a retryable transient — the operator advice was wrong. With (1)+(2) the original error survives; assert the classification names the true cause and retry-ability.

Also: bound/cache the manifest sweep that probes every historical rc tag on prerelease boxes (service.go:4567 area; rune probes 198 tags vs the smoke shape's 10) — an avoidable request amplifier that raises transient-collision odds.

Note the deployment asymmetry honestly: the first hop off v2026.08.1-rc.01 runs the OLD binary's preswap, so these fixes protect hops AFTER the fleet takes a fixed version — which is why they ride the next candidate now.

Acceptance: regression test injecting a RETURNED fetch error (not a kill) after DB stop → clean rollback, original git error preserved in the row's error, no panic (the rune signature reproduced then fixed); local-objects fast path proven (no network call when objects exist); transient fetch retries bounded-then-fails-cleanly; go test + the 0-happy-upgrade smoke green.
<!-- SECTION:DESCRIPTION:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Landed, foreman-reviewed: preswap object-ensure hoisted before the maintenance boundary (local cat-file fast path, zero network in the normal case; bounded stall-detected retries on a miss); rollback + Run defers nil-safe; OriginalError carried on the held flag (survives the process-death gap) so recovery reports the true cause as GIT_FETCH_FAILED_RETRYABLE with honest reschedule advice; manifest sweep bounded to tags newer than installed (198→10-ish probes on rune). Eight regression tests pin the rune signature; full cli suite + lint clean. Rides rc.03. Deployment asymmetry recorded in the ticket: the first hop off old binaries still runs old preswap; protection begins once the fleet takes a fixed version.
<!-- SECTION:NOTES:END -->
