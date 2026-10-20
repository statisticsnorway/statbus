---
id: STATBUS-522
title: >-
  Checking for upgrades is fast, checks only the newest release, and says what
  it knows
status: To Do
assignee: []
created_date: '2026-10-20 20:35'
updated_date: '2026-10-20 20:43'
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
A box checking for upgrades answers in seconds, checks only the release it would install, says plainly what it knows about each release, and can check any other release on request.

### Zoom out
The upgrade service discovers release tags, checks that each one's images and release files exist, and offers ready releases to the operator. Today the check is slow and repeats work:
- **Measured on an old box (v2026.09.2):** 24 newer release candidates sat `available` and were all checked, 12-14 s each, about 5 minutes, although only the newest would be installed.
- **Why so many rows:** every supersede rule is anchored on a row that was scheduled, completed or installed. Discovering a newer tag supersedes nothing.
- **Why so slow:** `verifyArtifacts` (`cli/internal/upgrade/service.go`) runs `docker manifest inspect` four times per row in series, 3.3-3.7 s each. The same answer costs 0.31 s from `release-manifest.json`, or 0.45 s per image from `ghcrManifestExists` (`ghcr.go`), which today is only the fallback.
- **Why the states mislead:** `docker_images_status` and `release_builds_status` use `building` for "not seen yet", and nothing ever writes `release_builds_status = failed`. The admin page says "Images building" when nobody knows whether a build runs.
- **Why the manifest is not the whole release:** `release-manifest.json` lists five images and omits the seed, although the RC gate (`cli/internal/release/check.go`) already requires six. `release.yaml` rebuilds and re-pushes four images that `images.yaml` already published for the same commit, so the tag moves to a new digest a day later.

Design record with measurements and options: `tmp/lxd-gate-design.md`, sections "T4 grounded", "T4 round 2", "T4 round 3".

### Zoom in: architecture (owner decisions 2026-10-17 and 2026-10-20)
1. **Only the newest release is checked automatically.** When discovery inserts a newer on-channel tag, older `available` rows become `superseded` through the existing `upgrade_supersede_older`. History stays complete. Rows already on real boxes are fixed by a forward migration.
2. **Readiness is decided by the cheapest true source.**
   - Tagged release: ready when `release-manifest.json` exists (`release.yaml` publishes it only after the images and binaries). No registry probe.
   - Untagged commit (arc fixtures, `./sb upgrade register <commit>`): `ghcrManifestExists` per image, all images in parallel. `docker manifest inspect` leaves the check.
   - The claim-time manifest fetch (`executeUpgrade`, STATBUS-336) and the image claim gate stay as they are.
3. **Check one release on request.** `./sb upgrade check <target>` and a Check button per row run the readiness check for that row only, without changing its lifecycle state. Scheduling stays `upgrade_schedule`, which already re-arms a superseded row.
4. **Readiness states say what is known.** Both columns stay separate (they answer different questions by different mechanisms). Values: `unchecked` (nobody looked), `pending` (looked, no build started), `building` (a build is running), `ready`, `failed`. `pending` and `building` need a published build status, which is the status-endpoint work (todo D); until then the box reports `unchecked`, `ready` and `failed`, and the admin page text matches.
5. **The manifest names the whole release, and images are built once.** `release-manifest.json` lists all six images including seed. `release.yaml` stops building images: it verifies that `images.yaml` published all six for the commit (the RC gate's check already requires this) and references them.

### Zoom in: test plan
- **SQL (`./dev.sh test`):** a new test in `test/sql/` for supersede-on-discovery: given rows for three tags, inserting the newest leaves exactly one `available`; a superseded row re-arms through `upgrade_schedule`; the forward migration supersedes old `available` rows on a seeded set. Existing `130_statbus_435_version_first_upgrade_supersession` and `327_test_upgrade_procedures` stay green.
- **Go:** `verifyArtifacts` with a fake registry (`httptest`) and a fake manifest fetch: a tagged row becomes ready from the manifest with no registry call; a commit row uses parallel HEAD probes; indeterminate is never read as absent. A test that the check for one row leaves `state` unchanged.
- **Real box:** an LXD guest at the previous stable, with several newer RCs present, runs one check: one row checked, total under 5 s, recorded with timings. The release-manifest change is shown on the next RC: the manifest lists six images whose digests equal the `images.yaml` ones.

### Zoom in: order of work
1. Supersede on discovery plus the forward migration (SQL first, then the `discover()` call).
2. Fast readiness check (manifest for tags, parallel HEAD for commits).
3. Check one release on request (CLI, then admin page).
4. Manifest names six images; `release.yaml` stops rebuilding.
5. Readiness state names, after the status endpoint is decided.

### Closing review
- **Memory:** none needed.
- **Documentation:** `doc/upgrade-timeline.md` describes discovery, readiness and the check action as built; `COMMENT ON` the readiness enum values states what each means.
- **Cleanup:** remove the `docker manifest inspect` path from `verifyArtifacts`.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Write SQL tests that discovering a newer tag leaves only the newest row available, that a superseded row re-arms through upgrade_schedule, and that a forward migration supersedes old available rows; record them failing before the change
- [ ] #2 Make discovery supersede older available rows and add the forward migration; the SQL tests and the existing upgrade tests pass
- [ ] #3 Write Go tests that a tagged row becomes ready from the release manifest with no registry call, and a commit row from parallel ghcr HEAD probes where indeterminate is never absent; then change verifyArtifacts so they pass and remove docker manifest inspect from it
- [ ] #4 Add ./sb upgrade check <target> and a Check button per row in the admin upgrades page that check one row without changing its state, with a Go test of the unchanged state
- [ ] #5 List all six images including seed in release-manifest.json and make release.yaml verify the images images.yaml published instead of building them; shown on the next RC by manifest digests equal to the images.yaml digests
- [ ] #6 Rename the readiness values to unchecked, pending, building, ready and failed, with COMMENT ON for each, and make the admin page text match what is known
- [ ] #7 On an LXD guest at the previous stable with several newer RCs present, one upgrade check checks one row and finishes in under 5 s; run and timings recorded in Implementation Notes
- [ ] #8 [Owner] Review the architecture, test plan and order of work in this ticket and record approval or changes in Implementation Notes before implementation starts
<!-- AC:END -->
