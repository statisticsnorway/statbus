---
id: STATBUS-367
title: >-
  The seed image is one data-only multi-arch manifest, so arm64 developers
  restore it too
status: Done
assignee: []
created_date: '2026-09-14 10:14'
updated_date: '2026-10-20 20:53'
labels:
  - release-bug
  - ci
  - dx
dependencies:
  - STATBUS-368
priority: medium
type: bug
ordinal: 30
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
### North Star
Every developer, on an amd64 or an arm64 machine, gets the published seed for their commit in seconds instead of replaying every migration.

### Zoom out
The seed image is pure data: a `pg_dump` and a small JSON file, only ever copied out with `docker create` and `docker cp`, never run. Data has no CPU architecture, so it should not have one in the registry either. Owner ruling (2026-09-14): build it once as a scratch image, and publish one multi-arch index whose amd64 and arm64 entries both point at that same single digest. Then any host's Docker resolves it natively, and no `--platform` pin is needed in the fetch code.

A fetch that fails must also say why: "not built for this commit" is a different situation from "Docker could not pull", and the old code reported both as the first.

### Zoom in
- **Incident, 2026-09:** `images.yaml` built the seed for `linux/amd64` only (since `463edb9b7`), so on an arm64 Mac `./sb db seed fetch` failed with `no matching manifest for linux/arm64/v8`. `dev.sh` read every fetch failure as "no seed image for this commit" and fell back to a full replay.
- **Interim fix (`0e07df223`, 2026-09-22):** pinned pull and create to `--platform linux/amd64`. That stopped the failure but did not meet the ruling.
- **Shipped (v2026.09.3):** `c57e12f04`, `2fe060ea5`. The seed stage is `FROM scratch` with `/seed.pg_dump` and `/seed.json` only; Images builds the payload once and PUTs an OCI index with amd64 and arm64 descriptors for the same digest (`.github/workflows/images.yaml`). `cli/cmd/seed.go` has no `--platform`, and a pull error distinguishes a missing manifest from other failures.
- **Observed 2026-10-15 (arm64 Mac, read-only):** `docker buildx imagetools inspect ghcr.io/statisticsnorway/statbus-seed:3b17af17` (v2026.10.1) is an OCI index whose `linux/amd64` and `linux/arm64` entries both resolve to `sha256:aead373ca7def938acdca171aa98b13780f8b433a0cda47a892cd2c7fd7bf82a`, a manifest with exactly 2 layers. `rg -- --platform cli/cmd/seed.go` finds nothing. A plain `docker pull` of that tag on the arm64 Mac succeeds without `--platform` (the image reports `amd64`, 2 layers, by design: both entries point at the one amd64-built payload).
- **Proof, unit:** `TestSeedFetchDockerArgsUseHostPlatformManifest`, `TestSeedPullErrorDistinguishesMissingManifest` (`cli/cmd/seed_image_test.go`), green 2026-10-15.

### Closing review
- **Memory:** none needed.
- **Documentation:** the `sb db seed` help states the image is not runnable and must be fetched.
- **Cleanup:** none.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 The published seed for a post-fix commit is one OCI index whose amd64 and arm64 entries reference one image digest with only the two data layers (observed for `statbus-seed:3b17af17`, 2026-10-15)
- [x] #2 `./dev.sh build-sb` on an arm64 Mac at a published commit restores the fetched seed (one pg_restore, no full replay), with no `--platform` in `cli/cmd/seed.go`
- [x] #3 A fetch at an unbuilt commit says the seed is not built; a fetch failing for another reason prints that reason (`TestSeedPullErrorDistinguishesMissingManifest`)
- [x] #4 [Owner] Decide whether an adversarial review by a different session is still required, and record it in Implementation Notes. No: check this. Yes: add the review as a new criterion.
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
### Evidence
- **AC1:** observed 2026-10-15 with `docker buildx imagetools inspect` and a plain `docker pull` on an arm64 Mac (Zoom in).
- **AC2:** open. Remaining observation: one `./dev.sh build-sb` on this arm64 Mac at a published commit, logging one seed restore. Not run during vetting because it rebuilds the local development database.
- **AC3:** green locally 2026-10-15.
- **History:** the 2026-09-14 build-and-hold notes, batch sequencing and 09-22/23 updates are in Git history.

### Owner decision 2026-10-20: no further adversarial review
The fix is in and tested (AC1, AC3). Remaining: AC2, a practical check of `./dev.sh build-sb` on the arm64 Mac, run by rabbit.

### AC2 observed 2026-10-20 on the arm64 Mac (rabbit)
Scratch worktree at published commit 4bb58264, own slot s367, so the shared local database was untouched.
- `./dev.sh build-sb` fetched `statbus-seed:4bb58264` on darwin/arm64 (`Seed fetched from image: migration 20261018113522`), with no `--platform` in `cli/cmd/seed.go`.
- `./dev.sh create-db` restored it once (`Seed restored to statbus_local (migration 20261018113522)`), then `Checking database migrations ... ok (0 pending)`: no replay. Logs: `tmp/367-build-sb-green.log`, `tmp/367-create-db-green.log`.
- Found and fixed on the way (43567fdef): create-db-structure rebuilt the database name as `statbus_<slot code>` instead of using POSTGRES_APP_DB, so any slot whose app database has another name failed after the restore (`tmp/367-create-db.log`). Green after the fix: the JWT secret and slot code land in the app database.
<!-- SECTION:NOTES:END -->
