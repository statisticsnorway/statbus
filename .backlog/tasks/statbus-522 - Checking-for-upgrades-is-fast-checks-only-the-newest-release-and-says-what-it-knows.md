---
id: STATBUS-522
title: >-
  Checking for upgrades is fast, checks only the newest release, and says what
  it knows
status: To Do
assignee: []
created_date: '2026-10-20 20:35'
updated_date: '2026-10-21 11:56'
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
- **Unclear words:** "building" means "not seen yet", not "a build is running".

Measurements: `tmp/lxd-gate-design.md` ("T4 grounded", "T4 round 2", "T4 round 3"). First design review: `tmp/review-522-gpt61sol.md`.

### Zoom in: the design
1. **Discovery retires only older available rows.**
   - A new step, used only by discovery, retires `available` rows older than the newest release on the box's channel. It is separate from `upgrade_supersede_older`, which also retires scheduled, failed and rolled-back rows and belongs to scheduling.
   - Order is the existing version order (`upgrade_version_key`, then commit time). The step re-checks `state = 'available'` in the same statement, so a row scheduled meanwhile is left alone.
   - Scheduled, in-progress, failed, rolled-back and parked rows are never touched.
   - A migration fixes rows already on boxes. It cannot know the box's channel, so it retires only available rows older than the newest available stable release, which is right on both channels. The service then narrows further on its next pass. The migration uses only stored values, never row IDs, and running it twice changes nothing.
2. **The manifest proves a whole release.**
   - `release.yaml` checks that all six images of the commit (app, db, worker, proxy, sb, seed) can be pulled anonymously, using the release gate's own check (`cli/internal/release/check.go`), before it publishes anything. It no longer builds images, and it lists all six in the manifest.
   - The box checks a manifest before trusting it: the right commit, the required images and binaries. Five-image manifests from older releases are still accepted.
   - Install keeps its own seed lookup and its fallback to full migrations. Untagged test commits need no seed.
3. **One fast check, used everywhere.**
   - A tagged release is ready when it has a valid manifest.
   - An untagged commit is checked with one existence probe per image (`ghcrManifestExists`), all at once and with a time limit. It is ready only when every image is present. An unclear answer changes nothing.
   - This one check replaces the per-tag manifest sweep and `docker manifest inspect`, for discovery, the idle heartbeat and the schedule gate.
   - It covers the newest available release plus any release someone registered, asked to check, or scheduled.
   - "Ready" means "was published". The image pull just before an upgrade stays the final safety check.
4. **Check or schedule one release on request.**
   - `./sb upgrade check <target>` and a Check button per row send a request for that one release: a new admin-only function that names the commit. The service checks that row only and does not change its lifecycle state. A row marked failed can be checked again.
   - Retired releases in the history list get the Check and Schedule buttons. The database still refuses a release older than the one installed.
5. **Clear words, same stored values.**
   - Older services accept only `building`, `ready` and `failed` (v2026.09.2 included), so the stored values stay.
   - The admin page and CLI show "not seen yet", "ready" and "not found". For an untagged commit, the release column shows "not applicable".

**Not in this ticket:** renaming the stored values and showing "pending" or "building" for real. That needs a published build status and comes with the status endpoint work.

### Zoom in: how we test it
- **SQL, with the triggers on:**
  - Discovery retires older available rows and leaves scheduled, in-progress, failed, rolled-back and parked rows as they were, also after repeated passes.
  - On the stable channel, a newer release candidate does not retire the newest release.
  - Edge rows: a release candidate promoted to a release (same commit), a missing version, equal commit times.
  - The migration on old-style rows gives the same result on full replay and on upgrade, and a second run changes nothing.
- **Go:**
  - Manifest checking: an empty manifest, the wrong commit, a missing binary, an old five-image manifest, a network error.
  - The probe with mixed present, absent and unclear answers.
  - Discovery fetches only the newest release's manifest. A one-row check changes only that row.
- **Workflow:** the six-image check refuses a commit with one image missing.
- **Browser:** Check, then Schedule, on a retired release in the history list.
- **Real box:** an LXD guest with the previous stable's database, several newer release candidates and the candidate's service. One check finishes in under 5 s, from request until the readiness is written, on a healthy network. Pre-download still pulls only the newest ready release.

### Zoom in: order of work
1. Discovery retires older available rows, plus the migration (SQL tests first).
2. `release.yaml` checks six images, stops rebuilding, lists six. The box checks manifests.
3. The shared fast check.
4. Check and Schedule one release, CLI and admin page.
5. Clear words.
6. Real-box timing and the next release candidate's manifest.

### Closing review
- **Memory:** none needed.
- **Documentation:** `doc/upgrade-timeline.md` describes discovery, readiness and the check as built.
- **Cleanup:** remove `docker manifest inspect` and the per-tag manifest sweep from the service.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Write SQL tests, with triggers on, for discovery retiring only older available rows (other states untouched across repeated passes, the stable channel, promoted, version-less and equal-time rows) and for the migration (same result on replay and upgrade, idempotent); record them failing before the change
- [ ] #2 Add the discovery-only retirement step and the forward migration; the new SQL tests and the existing upgrade SQL tests pass
- [ ] #3 Make release.yaml check that all six images of the commit can be pulled anonymously before it publishes, stop building images and list all six; a test shows the check refuses a commit with one image missing
- [ ] #4 Make the box check a fetched manifest (commit, images, binaries; five-image manifests accepted), shown by Go tests for empty, wrong-commit, incomplete and old manifests and a network error
- [ ] #5 Replace the per-tag manifest sweep and docker manifest inspect with one shared per-row check; Go tests show discovery fetches only the newest release's manifest and that mixed present, absent and unclear probe answers give the right result
- [ ] #6 Add ./sb upgrade check <target>, an admin-only function that names one commit, and Check and Schedule buttons for available and retired rows; tests show only that row's readiness changes and the Check then Schedule path works in the browser
- [ ] #7 Show readiness in plain words in the admin page and CLI without changing the stored values; app and Go tests cover the wording for tagged releases and untagged commits
- [ ] #8 On an LXD guest with the previous stable's database and several newer release candidates, the candidate's service finishes one check in under 5 s, and the next release candidate's manifest lists six images whose tags the release run did not move; run IDs and timings in Implementation Notes
- [ ] #9 [Owner] Review the rewritten design, test plan and order of work after the second review, and record approval or changes in Implementation Notes before implementation starts
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
2026-10-21 rewritten after the GPT 6.1 Sol design review (tmp/review-522-gpt61sol.md), owner-approved direction: discovery-only retirement of available rows (not upgrade_supersede_older); release.yaml checks six images before publishing and the box validates manifests, before manifest-based readiness; one shared per-row check; targeted Check plus Schedule for retired rows; plain words without changing stored values (older services parse building/ready/failed strictly, v2026.09.2 included). Stored-value rename and real pending/building move to the status endpoint work. Second review requested by the owner before approval.
<!-- SECTION:NOTES:END -->
