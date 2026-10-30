---
id: STATBUS-443
title: >-
  Inline scheduled dispatch after an installer checkout refuses source capture,
  because the tree renders neither the containers nor the target
status: Done
assignee: []
created_date: '2026-10-02 17:25'
updated_date: '2026-10-03 09:16'
labels:
  - upgrade
  - install
  - capture
  - field-report
dependencies: []
references:
  - STATBUS-436
  - STATBUS-441
priority: high
---

## Issue

The official repair sequence was register, then schedule (daemon down), then the version-pinned `install.sh`. With it, `./sb install`'s inline dispatch stops at the source-identity capture before anything destructive happens:

    Dispatching scheduled upgrade id=2 to 7ec86ac2... (commit 7ec86ac2)
    Bringing the database schema up to the daemon floor before the upgrade claim ...   (2 applied — STATBUS-441 fix works)
    M Upgrading to v2026.10.0-rc.12 (from v2026.10.0-rc.12)
    M Writing lock file for exclusive upgrade ... ok
    Installation stopped: Could not record immutable source image identities before target pull:
      source serving era cannot be established: restored source compose image for app is
      "ghcr.io/statisticsnorway/statbus-app:fe4a769a" (tag "fe4a769a"), want source commit 7ec86ac2,
      immutable digest, or explicit local image

## Mechanism (from source and the guest's bundle)

- `install.sh` (rescue mode) replaces `./sb` and checks out the target commit (`7ec86ac2`). It does **not** run `./sb config generate`, so the generated `.env` still carries `COMMIT_SHORT=fe4a769a` (support bundle line 1495), and compose renders `statbus-app:fe4a769a` from the target tree.
- `resolveSourceServingImageIdentities` (service.go ~9379) correctly captures the containers' `.Config.Image` (`…:fe4a769a`), the STATBUS-436 fix. It then calls `sourceServingExpectedImageReferences`, which requires the rendered tag to equal **`git rev-parse HEAD`** (`7ec86ac2`), an immutable digest, or `local`. The rendered tag is `fe4a769a`, so that check returns the error before either of the two accepted shapes is even compared:
  - `treeMatchesContainers`: the tree renders exactly what the containers run. This case is true here, since both say `fe4a769a`.
  - `treeRendersTarget`
- The comment at ~9375 says operator-inline dispatch "has already checked out Target before entering this pipeline". So the inline-after-checkout case was intended. But the corroboration helper assumes `.env` was regenerated together with the checkout. The unit test `TestCaptureSourceServingImageIdentitiesAcceptsInlineTargetTree` models the compose render with the target tag (shim `treeTag = targetTag`), which is not what a real `install.sh` rescue leaves behind.
- The arcs never take this path. They schedule and run `./sb install` from the **source** tree (no prior checkout), so HEAD, `.env`, and the containers all agree.

## Scope

- **Affected:** register, schedule, then `install.sh --version <target>` on any box, i.e. the scheduled-row path documented as "schedule, then `./sb install` to dispatch immediately" whenever it is entered through `install.sh`. Present since `3d393d725` (2026-09-19); shipped in v2026.09.3 and every rc since.
- **Not affected:**
  - The daemon path (capture runs before checkout).
  - Plain `./sb install` with no prior checkout (arcs).
  - The version-pinned install with **no** scheduled row, i.e. `./cloud.sh install <box> <tag>`. The STATBUS-436 operator-path proof passed against rc.12, and that path never reaches executeUpgrade.
- **Failure mode:** parks the claimed row (deterministic pre-destructive failure) and removes the flag. Nothing destructive ran and containers keep serving the source. The operator sees "Installation stopped", and the box is left at the target checkout with source containers.

## Principled fix (to decide, with review)

The capture's job is to record what the containers run. The tree is corroboration only. Two candidates:
1. Corroborate against the rendered compose model on its own terms: accept when the rendered references equal the containers' references (`treeMatchesContainers`), whatever HEAD says, and only demand HEAD's tag when deciding `treeRendersTarget`. Keep fail-closed for a render that matches neither.
2. Regenerate `.env` in `install.sh` rescue mode right after the checkout (so the tree renders the target and `treeRendersTarget` holds). This changes installer behavior for every rescue, so it needs its own review.

Option 1 is the narrower change and matches the documented intent ("the current tree is only corroboration").

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 A unit test with the docker shim reproduces the real shape (HEAD = target, rendered compose tag = source = containers' `.Config.Image`), fails on current master with this exact error, and passes after the fix.
- [x] #2 The genuine-ambiguity refusals stay fail-closed: a render that matches neither the containers nor the target, mixed container tags, a digest without a tag, and a tagless reference all still refuse.
- [x] #3 The STATBUS-436 scheduled-path guest proof (`CANDIDATE_PATH=scheduled`) passes against a candidate carrying the fix: the carrier binds every service's exact pre-pull identity, the upgrade completes, the box stays healthy across scheduler ticks, and the 441 floor line precedes the claim in the transcript (closes 441 AC#2).
<!-- AC:END -->

## Implementation Notes

2026-10-03 09:16 UTC: fixed with option 1. `resolveSourceServingImageIdentities` now corroborates against `sourceServingRenderedImageReferences`, the raw compose render with no HEAD-tag requirement. It accepts exactly two shapes: all-service equality between the render and the containers' references, or the existing strict target render. Every other render still refuses. The target-era and restored-source callers keep the strict `sourceServingExpectedImageReferences`.

New shim regression: HEAD is the target, while the rendered tree, the containers' Config.Image and the immutable IDs are all the source. It reproduces the field refusal on the parent and passes with the fix. The mixed-tag and unrelated-tree refusals still hold.

Independent review: MERGE (`tmp/443-review.md`). Merged as eb99b03a9 (patch-id equal to the reviewed 682b41d09); merged-tree `go test ./cmd ./internal/migrate ./internal/upgrade ./internal/install` passed. AC#3 (scheduled-path guest proof against the candidate) runs against rc.13.

2026-10-06 08:05 UTC, v2026.10.0-rc.16 (`7e92d1151`) evidence:
- Release gates all green. Orchestrator run 37424897889: decision, smoke, dev canary, LXD fault fleet (run 37426559632) and arc harness (run 37426638674, 06:56 to 07:51 UTC, 41 success, 0 failure).
  - The 9 arcs that failed on rc.15 all passed: postswap-between-migrations-kill, postswap-mid-migration-kill, boot-migrate-churn-alive-idle, flagless-selfheal-at-target, postswap-converged-selfheal, postswap-container-restart-kill, postswap-mid-tx-kill, preswap-fetch-returned-error and restore-broke-reattempt.
  - So did the 8 that never ran on rc.15: preswap-checkout-kill, rollback-pair-terminal, rollback-kill, un-park-to-completion, transient-db-backoff, worker-wedge-mid-derive, rollback-schema-floor-failure and working.
- STATBUS-436 operator rehearsal: PASS 06:42 to 07:00 UTC, single installer run, no retry (`tmp/436-operator-rc16.PASS.log`). The old daemon was refused during the install with "another ./sb install is already running (install, invoked_by=install.sh:statbus)", the v2026.09.3 row ended superseded, and there were zero refusals and zero re-attempts afterwards.
- STATBUS-436 scheduled rehearsal: run 1 (06:42 to 06:57) completed the product path, but the test's own carrier check ran `jq` inside the hardened guest, which has none (rc=127). That line had never been reached before. The check was fixed test-only to parse the carrier on the host (`test: parse the 436 capture carrier on the host`, review `tmp/436-jq-review.md` MERGE). Run 2 (07:01 to about 07:15) used the rc.16 product with only that test file overlaid, and PASSED (`tmp/436-scheduled-rc16.PASS.log`):
  - "Continuing the upgrade on the new binary after the planned handoff."
  - 18/18 steps.
  - The carrier binds the exact reference and immutable ID for app, worker, rest and proxy.
  - The resident program is v2026.10.0-rc.16 at ~/statbus/sb.
  - The health check passed at all 4 sustained checks, with no daemon restart.
