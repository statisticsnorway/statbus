---
id: STATBUS-522
title: >-
  Checking for upgrades is fast, checks only the newest release, and says what
  it knows
status: To Do
assignee: []
created_date: '2026-10-20 20:35'
updated_date: '2026-10-21 12:12'
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
- **Too many rows:** finding a newer release does not retire the older ones. An old box (v2026.09.2) kept 24 release candidates open and checked them all.
- **A slow check:** each check runs `docker manifest inspect` four times in a row, about 14 s per release, so that box took 5 minutes. Discovery also fetches the manifest of every tag on every pass.
- **Weak proof:** `release.yaml` publishes `release-manifest.json` (the file that describes a release) without waiting for the sb and seed images, and lists only five images. The box accepts any manifest, even an empty one. `release.yaml` also rebuilds images that `images.yaml` already built, so the image tags move.
- **Unclear words:** "building" means "not seen yet", not "a build is running". A row marked failed is never checked again.

Measurements: `tmp/lxd-gate-design.md` ("T4 grounded", "T4 round 2", "T4 round 3"). Design reviews: `tmp/review-522-gpt61sol.md`, `tmp/review-522-gpt61sol-2.md`.

### Zoom in: the design
1. **Discovery retires only older available rows.**
   - A new step, used only by discovery, retires `available` rows older than the newest release on the box's channel. `upgrade_supersede_older` stays as it is; it also retires scheduled, failed and rolled-back rows and belongs to scheduling.
   - Compare release versions first (`upgrade_version_key` of the row's newest tag, so a promoted release counts as the release). Use commit time to break ties. A row without a version is compared by commit time only, as `upgrade_supersede_older` does.
   - If someone schedules a row during discovery, leave it scheduled: the step re-checks `state = 'available'` in the same statement. Scheduled, in-progress, failed, rolled-back and parked rows are never touched.
   - The migration does not know the box's channel. It keeps the newest available stable release and retires only older available rows. With no available stable release it changes nothing. The service applies the channel rules on its next pass. The migration uses stored values only, never row IDs, and a second run changes nothing.
2. **The manifest proves a whole release.**
   - Before publishing, `release.yaml` checks that all six images of the exact commit (app, db, worker, proxy, sb, seed) can be pulled anonymously. This is a new strict mode of the release gate's check (`cli/internal/release/check.go`), with no fallback to version-tag images. It refuses a missing, private or unclear image, and then nothing is published. `release.yaml` no longer builds images and lists all six in the manifest.
   - The box checks a manifest before trusting it: the right commit, the required images and the binaries. A release published before this change has a five-image manifest. The box accepts it but checks that release's images with the probe, as for a commit, and the seed stays optional (install falls back to full migrations). A new manifest without the seed is rejected.
   - Untagged test commits need no seed.
3. **One fast check, used everywhere.**
   - A tagged release with a new six-image manifest is ready from the manifest alone.
   - Otherwise the box probes each image (`ghcrManifestExists`) all at once, under one overall time limit that can be cancelled. Every image present: ready. Any image absent: not found. Any unclear answer: nothing changes.
   - This one check replaces the per-tag manifest sweep and `docker manifest inspect` for every caller: discovery, the idle heartbeat, the schedule gate, the inline install path, and the fallback when git discovery fails.
   - It checks the newest available release plus every release someone registered, asked to check, or scheduled, and any row where either readiness column is not yet ready.
   - "Ready" means "was published". The image pull before an upgrade stays the final safety check: if an image has gone, the pull fails, the running installation keeps serving, and nothing destructive starts.
4. **Check or schedule one release on request.**
   - `./sb upgrade check <target>` and a Check button per row call a new admin-only function that records a check request for that commit and wakes the service. The service checks that row only, records when the check finished and what it found, and does not change the row's lifecycle state. A request left over from a lost wake-up is picked up on the next pass.
   - A Check runs again even on a row marked ready or not found.
   - Retired releases in the history list get Check and Schedule. Available rows already have Schedule. The database still refuses a release older than the one installed.
5. **Clear words, same stored values.**
   - v2026.09.2 and the current service accept only `building`, `ready` and `failed`, so the stored values stay. Their meanings become: `building` = not seen yet, `ready` = present, `failed` = looked and not found (it no longer means a CI failure, and it can be checked again).
   - The admin page and CLI show "not seen yet", "ready" and "not found". An untagged commit's release column shows "not applicable".
   - The column comments say the same.

**Not in this ticket:** renaming the stored values and showing "pending" or "building" for real. That needs a published build status and comes with the status endpoint work (todo D).

### Closing review
- **Memory:** none needed.
- **Documentation:** `doc/upgrade-timeline.md` and the readiness column comments describe the check as built.
- **Cleanup:** remove `docker manifest inspect` and the per-tag manifest sweep from the service.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Write SQL tests with triggers on that name which commits stay available after discovery: older available rows retired; scheduled, in-progress, failed, rolled-back, parked and rollback-pending rows unchanged after repeated passes; a row scheduled during discovery stays scheduled; promoted, version-less and equal-time rows; the stable channel keeps the newest release; record them failing before the change
- [ ] #2 Write SQL tests for the migration: the same commits stay available after full replay, after an incremental upgrade, on rows written by an older service, and after a second run; nothing changes without an available stable release
- [ ] #3 Add the discovery-only retirement step and the forward migration; all new and existing upgrade SQL tests pass
- [ ] #4 Add the strict exact-commit mode of the release image check and run it in release.yaml before publishing; tests show it refuses a missing commit image even when a version-tag image exists, and refuses a private or unclear image, and that release.yaml then publishes nothing
- [ ] #5 Make release.yaml stop building images and list all six in the manifest; the next release candidate's run records the six image digests before and after publishing, and they are equal
- [ ] #6 Make the box check a fetched manifest; Go tests show a new six-image manifest is accepted, a genuine five-image manifest is accepted with its images probed, and an empty, wrong-commit or binary-less manifest, a new manifest without seed, and a network error each leave the row unchanged
- [ ] #7 Replace the per-tag manifest sweep and docker manifest inspect with one shared per-row check for all callers; Go tests show discovery fetches only the newest release's manifest, registered and scheduled rows still progress, both readiness columns progress, probes run together under one cancellable deadline, and all present gives ready, any absent gives not found, any unclear changes nothing
- [ ] #8 A Go test shows that when the image pull before an upgrade fails on a row marked ready, the running installation keeps serving and no destructive step starts
- [ ] #9 Add the admin-only check request function, ./sb upgrade check <target> and the Check and Schedule buttons for retired rows; tests show a non-admin is refused, only that row's readiness and check time change, a not-found row can be checked again, a request survives a service restart, and Check then Schedule works in the browser
- [ ] #10 Show readiness as "not seen yet", "ready" and "not found" ("not applicable" for an untagged commit's release column) in the admin page and CLI, and update the column comments and doc/upgrade-timeline.md; app and Go tests show each stored value maps to its word
- [ ] #11 Run the candidate service on an LXD guest upgraded from the previous stable, with several newer release candidates and a healthy network: readiness is saved within 5 s of the request and pre-download fetches only the newest ready release; record the image commit, the rows before and after, and the timings in Implementation Notes
- [ ] #12 [Owner] Review the design after both reviews. Approval starts implementation at criterion 1; requested changes go back into the design first. Record the decision in Implementation Notes
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
2026-10-21 rewritten after the GPT 6.1 Sol design review (tmp/review-522-gpt61sol.md), owner-approved direction: discovery-only retirement of available rows (not upgrade_supersede_older); release.yaml checks six images before publishing and the box validates manifests, before manifest-based readiness; one shared per-row check; targeted Check plus Schedule for retired rows; plain words without changing stored values (older services parse building/ready/failed strictly, v2026.09.2 included). Stored-value rename and real pending/building move to the status endpoint work. Second review requested by the owner before approval.

2026-10-21 second GPT 6.1 Sol review (tmp/review-522-gpt61sol-2.md) folded in. Blocker fixed: release.yaml uses a new strict exact-commit mode of the image check (CheckManifests falls back to version-tag images, check.go:127-145). Also: version order uses the row's newest tag; old five-image manifests are accepted but their images are probed; one cancellable deadline; durable per-row check requests with completion and restart recovery; failed = looked and not found, and can be checked again; the pull-before-upgrade safety test; digest before/after comparison. Criteria now state observable results.
<!-- SECTION:NOTES:END -->
