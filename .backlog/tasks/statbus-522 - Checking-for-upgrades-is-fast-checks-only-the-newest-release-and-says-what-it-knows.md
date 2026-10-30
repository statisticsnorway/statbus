---
id: STATBUS-522
title: >-
  Checking for upgrades is fast, checks only the newest release, and says what
  it knows
status: To Do
assignee: []
created_date: 2026-10-20 20:35
updated_date: '2026-10-30T12:36:00Z'
labels:
  - upgrade
  - release
dependencies: []
priority: high
type: enhancement
ordinal: 448204
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
### North Star
Checking for upgrades takes seconds. The box checks only the release it would install, says plainly what it knows, and can check or schedule any other release when asked.

### Zoom out
A box finds new releases, checks that each one's files and images exist, and offers the ready ones. Four things make this slow or unreliable:
- **Too many rows:** finding a newer release does not retire the older ones. Every retirement rule is anchored on a row that was scheduled, completed or installed. An old box (v2026.09.2) kept 24 release candidates open and checked them all.
- **A slow check:** `verifyArtifacts` runs `docker manifest inspect` four times in a row per row, 3.3-3.7 s each, about 14 s per release, so that box took 5 minutes. Discovery also fetches the manifest of every newer tag on every pass, whatever the row's state.
- **Weak proof:** `release.yaml` publishes `release-manifest.json` (the file that describes a release) without waiting for the sb and seed images, and lists only five images. The box accepts any manifest that decodes, even `{}`. `release.yaml` also rebuilds four images that `images.yaml` already built for the same commit, so their tags move to new digests a day later.
- **Unclear words and a dead end:** "building" means "not seen yet", not "a build is running". A row marked failed is never checked again, and nothing explains the failure.

**Principles agreed with the owner (2026-10-17 to 2026-10-21):**
- Check only what the box would install; anything else only when someone asks.
- Decide from the cheapest true source, and never read an unclear answer as an answer.
- Every word the box shows is something it actually knows.
- Change stored values only when older services can read them.
- One build per commit; a release only references what CI already built.

**Background:** measurements and options in `tmp/lxd-gate-design.md` ("T4 grounded", "T4 round 2", "T4 round 3"). Design reviews: `tmp/review-522-gpt61sol.md` (12 findings, 3 blockers) and `tmp/review-522-gpt61sol-2.md` (1 blocker), all folded in below. Build status for display (queued, building, build failed) is STATBUS-525.

### Zoom in: how it works today (code read on master `fc8151feb`, 2026-10-30)
| Piece | Where | What it does |
|---|---|---|
| Discovery | `discover()`, `cli/internal/upgrade/service.go:5992` | `git fetch --tags`, inserts rows for on-channel tags newer than installed, then fetches `release-manifest.json` for every such tag (`:6167`) to set `release_builds_status` |
| Readiness check | `verifyArtifacts()`, `service.go:2811` | selects up to 30 rows with `docker_images_status != 'ready'`, any state; 4 x `docker manifest inspect` (db, app, worker, proxy); a row already `failed` is skipped (`:2875`); after 20 min of confirmed absence it writes `failed` |
| Fast probe | `ghcrManifestExists()`, `ghcr.go:80`; `probeAllImagesGhcr()`, `ghcr.go:132` | anonymous token + HEAD per image, 0.45 s; present / absent / indeterminate; used only as a fallback, serially, each call with its own 15 s timeout |
| Claim gate | `evaluateImageClaimGate()`, `image_claim_gate.go:65` | a scheduled row waits while images are not ready, claims after the grace, refuses `failed`; reads the stored value, does not re-probe |
| Claim-time manifest | `service.go:8313`, `:8796`, `:14407`, `:14685` | refetches the manifest for the binary URL and sha256 before replacing `sb` |
| Final safety | warm-up image pull before destructive steps (`service.go`, executeUpgrade) | the real proof that images are pullable |
| Pre-download | `preDownloadImages()`, `service.go:6475` | pulls images of the newest ready candidate |
| Retirement | `upgrade_supersede_older(sha)`; `supersedeBelowInstalled()`, `service.go:6537`; `upgrade_supersede_completed_prereleases`; `upgrade_block_obsolete_pending` trigger | all anchored on a scheduled, completed or installed row; `upgrade_supersede_older` retires available, scheduled, failed and rolled-back rows |
| Check button | `upgrade_request_check()` = `NOTIFY upgrade_check`; handler `service.go:4226` runs `discover()` | global only, no row named, no result |
| CLI | `./sb upgrade check` (`cli/cmd/upgrade.go:92`) = `RunCheck` (`service.go:7380`): discover over git and register; `./sb upgrade list` shows readiness (`upgrade.go:283`) | |
| Stored values | `docker_images_status`, `release_builds_status`: `building` / `ready` / `failed`; parsed strictly by `ParseDockerImagesStatus` (`ledger_types.go:75`) and its twin, in the current service and in v2026.09.2 | |
| Manifest | `Manifest` struct, `github.go:29`; `FetchManifest`, `github.go:204` decodes without validating | written by `release.yaml` `create-release` (`needs: [metadata, image-manifest, build-binaries]`, line 208), images map lines 265-271: app, db, worker, proxy, sb |
| Producer gate | `CheckManifests` / `checkManifestsAt`, `cli/internal/release/check.go:68,131` | six images (app, db, worker, proxy, sb, seed), but falls back to the version-tag image when the commit image is missing; runs in the RC gate after publication |

### Zoom in: the design
**1. Discovery retires only older available rows.**
- A new procedure, `public.upgrade_retire_older_available(p_commit_sha text)`, used only by discovery. It retires rows with `state = 'available'` that are older than the given row, re-checking `state = 'available'` in the same `UPDATE`, so a row scheduled meanwhile stays scheduled.
- It never touches scheduled, in-progress, failed, rolled-back or parked rows, or rows with `rollback_finish_pending_at`. `upgrade_supersede_older` stays as it is for scheduling and completion.
- **Order:** compare `upgrade_version_key` of the row's newest tag (from `commit_tags`, so a candidate promoted to a release counts as the release); break ties by `committed_at`. A row whose version cannot be parsed is compared by `committed_at` only, as `upgrade_supersede_older` does. Rows with the same commit are the same release.
- **Channel:** discovery calls it with the newest row on the box's channel (stable: releases only; prerelease: releases and candidates), so on the stable channel a newer candidate never retires the newest release.
- **Migration for rows already on boxes:** it cannot know the box's channel, so it keeps the newest available stable release and retires only available rows older than it. With no available stable release it changes nothing. The service applies the channel rule on its next pass. It uses stored values only, never row IDs or discovery order, and a second run changes nothing. Retired rows keep their history and can be scheduled again through `upgrade_schedule`.

**2. The manifest proves a whole release.**
- **Producer:** before `create-release`, `release.yaml` runs a new strict mode of the release image check, `./sb release verify-commit-images <sha>`, built on the same probe as `check.go` but with no fallback to version-tag images. It requires all six images (app, db, worker, proxy, sb, seed) at the exact `commit_short`, anonymously pullable. A missing, private or unclear image fails the job, and nothing is published.
- `release.yaml` stops building images (`build-images` and `image-manifest` go). It references what `images.yaml` built, and the manifest's `images` map lists all six. Adding `seed` to the map is additive; `Manifest.Images` is already a map.
- The job records the six index digests it verified, and compares them again after publishing; the release run must not move any tag.
- **Consumer:** the box validates a manifest before trusting it: `commit_sha` equals the row's commit; binaries for its platform with a URL and sha256; and the images map. A manifest with six images is a "new" manifest. A five-image manifest is a release from before this change: it is accepted, but its images are probed like a commit's, and the seed stays optional (install keeps its own seed lookup and its fallback to full migrations). A new-shape manifest without the seed is rejected. Untagged test commits need no seed.

**3. One fast check, used everywhere.**
- One function checks one row: `checkRow(ctx, row) (readiness, error)`.
  - A tagged release with a valid six-image manifest: ready from the manifest alone, no registry call.
  - Otherwise: one `ghcrManifestExists` per required image, all at once, under one overall deadline from the caller's context. Every image present: ready. Any image absent: not found. Any unclear answer: nothing is written.
- It replaces the manifest sweep in `discover()` and `docker manifest inspect` in `verifyArtifacts()`, and every caller uses it: discovery, the idle heartbeat, the schedule gate, the inline install path, and the fallback when git discovery fails.
- **Which rows:** the newest available row on the channel, plus every row someone registered, asked to check (part 4) or scheduled, and only rows where either readiness column is not yet ready. Never a sweep of all rows.
- "Ready" means "was published". The pull before an upgrade stays the final safety check: if an image has gone, the pull fails, the running installation keeps serving, and nothing destructive starts.

**4. Check or schedule one release on request.**
- A new function `public.upgrade_request_row_check(p_commit_sha text)`, `SECURITY DEFINER`, `GRANT EXECUTE ... TO admin_user` only (as `upgrade_schedule`). It records the request on the row (`check_requested_at`) and sends `NOTIFY upgrade_check_row, '<sha>'`.
- The service handles `upgrade_check_row` by running `checkRow` for that row only, then writes `checked_at` and the result. It never changes `state` or recovery fields. On each pass it also picks up rows whose `check_requested_at` is later than `checked_at`, so a lost notification or a restart does not lose the request.
- An explicit check runs even on a row marked ready or not found; a not-found row can become ready.
- `./sb upgrade check <target>` calls the same function and waits for `checked_at` to pass the request time, then prints the result. `./sb upgrade check` without a target keeps today's meaning (discover and register).
- **Admin page:** a Check button on every row. Retired rows in the history list also get Schedule. The database still refuses a release older than the one installed (`upgrade_block_obsolete_pending`).
- An older service ignores `upgrade_check_row` and the new columns, so nothing breaks; the request simply waits for the new service.

**5. Clear words, same stored values.**
- The stored values stay `building`, `ready`, `failed`, because the current service and v2026.09.2 accept only these. Their meanings become: `building` = not seen yet, `ready` = present, `failed` = looked and not found (no longer "CI failed", and it can be checked again).
- The admin page and `./sb upgrade list` show "not seen yet", "ready" and "not found". An untagged commit's release column shows "not applicable".
- `COMMENT ON COLUMN` for both columns states these meanings; `doc/upgrade-timeline.md` describes discovery, readiness and the check as built.
- Showing queued, building or build failed for real comes from STATBUS-525 (display only), not from these values.

### Zoom in: order of work and how each step is proven
1. **Discovery retirement:** SQL tests first, failing; then the procedure, the discovery call and the migration. (criteria 1-3)
2. **Producer:** the strict check and `release.yaml` change; then the box's manifest validation. (criteria 4-6)
3. **Shared check:** `checkRow`, with all callers switched and the old code removed. (criteria 7-8)
4. **Check one row:** function, service handler, CLI and admin page together. (criterion 9)
5. **Words:** admin page, CLI, column comments and docs. (criterion 10)
6. **Real proof:** an LXD guest and the next release candidate. (criteria 11-12)

Each step lands on master on its own with CI green, in this order, so a manifest is never trusted before the producer guarantees it.

### Zoom in: compatibility and rollback
- **Older services reading new data:** the new columns (`check_requested_at`, `checked_at`) and procedures are ignored by older services, and the stored readiness values do not change. Retired rows are rows older services already know how to show.
- **Rolling back the service:** an older service keeps working on the same database; it returns to the slow check and its own words.
- **Old releases:** five-image manifests keep working through the probe; no release a box skipped becomes unusable.
- **Migration:** deterministic and idempotent on full replay and on incremental upgrade; tested on rows written by an older service.

### Zoom in: not in this ticket
- Showing queued, building or build failed: STATBUS-525.
- Renaming the stored readiness values: not needed once 525 provides the build status; revisit only if a real need appears.
- The release gate's own checks after publication stay as they are.

### Closing review
- **Memory:** none needed.
- **Documentation:** `doc/upgrade-timeline.md` (discovery, readiness, the check), `COMMENT ON` for both readiness columns and the new functions and columns.
- **Cleanup:** remove `docker manifest inspect` from `verifyArtifacts`, the per-tag manifest sweep from `discover()`, and the serial `probeAllImagesGhcr` once `checkRow` replaces it.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Write SQL tests with triggers on that name which commits stay available after discovery: older available rows retired; scheduled, in-progress, failed, rolled-back, parked and rollback-pending rows unchanged after repeated passes; a row scheduled during discovery stays scheduled; promoted, version-less and equal-time rows; on the stable channel a newer candidate leaves the newest release available; record them failing before the change
- [ ] #2 Write SQL tests for the migration: the same commits stay available after full replay, after an incremental upgrade, on rows written by an older service, and after a second run; nothing changes when no available stable release exists
- [ ] #3 Add upgrade_retire_older_available, call it from discovery with the newest row on the box's channel, and add the forward migration; all new and existing upgrade SQL tests pass
- [ ] #4 Add ./sb release verify-commit-images <sha> with no fallback to version-tag images; Go tests show it refuses a missing commit image even when a version-tag image exists, and refuses a private or unclear image
- [ ] #5 Make release.yaml run that check before create-release, stop building images, list all six in the manifest, and compare the six index digests before and after publishing; the next release candidate's run shows the check passing and equal digests, run ID in Implementation Notes
- [ ] #6 Make the box validate a fetched manifest; Go tests show a six-image manifest accepted as ready, a five-image manifest accepted with its images probed, and an empty, wrong-commit or binary-less manifest, a six-image-era manifest without seed, and a network error each leaving the row unchanged
- [ ] #7 Add checkRow and switch every caller to it (discovery, idle heartbeat, schedule gate, inline install, git-discovery fallback); Go tests show discovery fetches only the newest release's manifest, registered and scheduled rows still progress, both readiness columns progress, probes run together under one deadline, and all present gives ready, any absent gives not found, any unclear writes nothing
- [ ] #8 A Go test shows that when the image pull before an upgrade fails on a row marked ready, the running installation keeps serving and no destructive step starts
- [ ] #9 Add upgrade_request_row_check (admin_user only), the service handler, ./sb upgrade check <target> and the Check and Schedule buttons; tests show a non-admin is refused, only that row's readiness and checked_at change, a not-found row can become ready, a request made while the service is stopped is handled after it starts, and Check then Schedule works in the browser
- [ ] #10 Show readiness as "not seen yet", "ready" and "not found" ("not applicable" for an untagged commit's release column) in the admin page and ./sb upgrade list, and update the column comments and doc/upgrade-timeline.md; app and Go tests show each stored value maps to its word
- [ ] #11 Run the candidate service on an LXD guest upgraded from the previous stable, with several newer release candidates and a healthy network: readiness is saved within 5 s of the request and pre-download fetches only the newest ready release; record the image commit, the rows before and after, and the timings in Implementation Notes
- [ ] #12 Remove docker manifest inspect from verifyArtifacts, the per-tag manifest sweep from discover() and the serial probeAllImagesGhcr; rg finds none of them in cli/internal/upgrade outside tests
- [ ] #13 [Owner] Discuss the third review's findings with dolphin and record the agreed changes and approval in Implementation Notes. Approval starts implementation at criterion 1; agreed changes go into the design first
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
2026-10-21 rewritten after the GPT 6.1 Sol design review (tmp/review-522-gpt61sol.md), owner-approved direction: discovery-only retirement of available rows (not upgrade_supersede_older); release.yaml checks six images before publishing and the box validates manifests, before manifest-based readiness; one shared per-row check; targeted Check plus Schedule for retired rows; plain words without changing stored values (older services parse building/ready/failed strictly, v2026.09.2 included). Stored-value rename and real pending/building move to the status endpoint work. Second review requested by the owner before approval.

2026-10-21 second GPT 6.1 Sol review (tmp/review-522-gpt61sol-2.md) folded in. Blocker fixed: release.yaml uses a new strict exact-commit mode of the image check (CheckManifests falls back to version-tag images, check.go:127-145). Also: version order uses the row's newest tag; old five-image manifests are accepted but their images are probed; one cancellable deadline; durable per-row check requests with completion and restart recovery; failed = looked and not found, and can be checked again; the pull-before-upgrade safety test; digest before/after comparison. Criteria now state observable results.

2026-10-30 written out in full at the owner's request: how it works today (anchored on master fc8151feb), the five design parts with names (upgrade_retire_older_available, ./sb release verify-commit-images, checkRow, upgrade_request_row_check with check_requested_at/checked_at), order of work, compatibility and rollback, and what is out of scope (build status display is STATBUS-525). Next: a third, independent review, then the owner and dolphin discuss its feedback.
<!-- SECTION:NOTES:END -->
