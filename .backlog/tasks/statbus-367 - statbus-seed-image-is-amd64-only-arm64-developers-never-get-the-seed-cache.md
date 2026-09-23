---
id: STATBUS-367
title: >-
  statbus-seed image is amd64-only: arm64 developers never get the seed cache
  and are told the image does not exist
status: In Progress
assignee: []
created_date: '2026-09-14 10:14'
updated_date: '2026-09-23 15:10'
labels:
  - ci
  - dx
dependencies:
  - STATBUS-368
priority: medium
type: bug
ordinal: 30
---

## Ground truth

`images.yaml` builds the five service images for `linux/amd64,linux/arm64`.
The `seed` job (added `463edb9b7`, 2026-05-30) builds `statbus-seed` with
`platforms: linux/amd64` only. `docker manifest inspect
ghcr.io/statisticsnorway/statbus-seed:b6d81049` shows one platform, amd64.

On an arm64 Mac, `./sb db seed fetch` asks for the arm64 variant and gets
`no matching manifest for linux/arm64/v8`. `dev.sh` treats every fetch
failure as "no seed image for this commit" and falls back to a full
migration replay. Correct behaviour, wrong diagnosis, and the ~2 s restore
never happens for arm64 developers.

The image is `FROM busybox` carrying `seed.pg_dump` and `seed.json`. The
content has no architecture. It is only ever `docker create` + `docker cp`,
never run.

## Ruling (owner, 2026-09-14 10:43): data-only image, one build, multi-arch manifest

Correction to the ground truth above: `seed.go:184` already pins
`docker create --platform linux/amd64` with a correct comment; the
`docker pull` at `seed.go:124` before it has no pin, so on arm64 the pull
fails and `create` is never reached. That one-line gap is what arm64
developers hit.

Ruled design:

1. `postgres/Dockerfile` seed stage becomes `FROM scratch`, copying only
   `/seed.pg_dump` and `/seed.json`. No busybox, no binary, no
   architecture-specific byte in the image. Keep the `LABEL` description;
   the `CMD` usage text goes (nothing can execute from scratch), so the
   `doc`/`sb db seed` help must carry the "not runnable, use fetch" line.
2. `images.yaml` seed job builds ONCE (`platforms: linux/amd64`, as today),
   then publishes a multi-arch manifest referencing that single digest for
   both `linux/amd64` and `linux/arm64` via `docker buildx imagetools
   create` (the tree already uses it for tag aliasing). No second replay.
3. `seed.go`: the `--platform` pins on pull and create are removed; the
   manifest resolves on every platform. The fetch-failure message
   distinguishes "manifest unknown" (not built yet) from any other error.

Why not busybox multi-arch: two replays for identical payload. Why not the
pin alone: it makes arm64 a special case in code for an artifact that has
no platform.

## Done when

- `docker manifest inspect ghcr.io/statisticsnorway/statbus-seed:<short>`
  at a post-fix commit lists both amd64 and arm64 pointing at ONE image
  digest, and `docker image inspect` of it shows no layers beyond the two
  files.
- `./dev.sh build-sb` on an arm64 Mac at that commit restores the seed
  (create-db logs one pg_restore, not a full replay), with no `--platform`
  anywhere in `cli/cmd/seed.go`.
- A fetch at an unbuilt commit prints the not-built note; a fetch that
  fails for another reason prints that reason.
- Adversarial review by a different session. After the batch RC.

## Built and accepted, held in scratch until rc.05 is cut (2026-09-14 13:46)

Scratch `$JCODE_SCRATCH_DIR/statbus-367`, branch `statbus-367`, commits
`9c34ebea4` (FROM scratch seed stage, two files, LABEL kept, CMD gone; pins
removed from seed.go; manifest-unknown vs other error distinguished; help
carries the "not runnable, use fetch" line), `bfbf037e8`, `2fe06f637`
(images.yaml: build step `id: seed-build`, `provenance: false`; publish
step builds the OCI index from `steps.seed-build.outputs.digest` with
amd64 and arm64 entries at that one digest and PUTs it to ghcr with the
token mint pattern from ops/release/image-cleanup.yaml).

Finding on the way (duckling): `docker buildx imagetools create` de-
duplicates sources by digest (`util/imagetools/create.go addDesc`), so it
cannot express one digest under two platforms; verified against a local
registry:2. Hence the raw index push. Local proof: the index lists both
platforms at one digest and `docker create` resolves it on arm64.

Luna (pawprint) round 1 REJECT (digest taken by inspecting the tag), round
2 ACCEPT: `tmp/STATBUS-368-367-review.md`. Only a real Images run proves
the ghcr publish and the arm64 `build-sb` single pg_restore; that is the
first master push after landing.

## Batch sequencing (owner ruling 2026-09-15)

This ticket lands in the ONE batch after the current release: it does not
touch master until v2026.09.1-rc.08 (or the first later rc that goes fully
green) has been installed on Norway and promoted to stable. Then all batch
tickets land in one push, one candidate, one ladder. Position in that push:
**3 of 8**. seed image FROM scratch + multi-arch manifest; built and Luna-accepted in scratch (9c34ebea4, bfbf037e8, 2fe06f637); the batch push is its ghcr proof

Batch order: 370 -> 368 -> 367 -> 363 -> 357 -> 361 -> 362 -> 359.

## Update 2026-09-22

The arm64 fetch failure was fixed on master by `0e07df223` (`seed: pin fetch
image platform`). Both `docker pull` and `docker create` now use
`--platform linux/amd64`, with focused argv tests in
`cli/cmd/seed_image_test.go`.

Status remains **In Progress** under this file's own acceptance criteria. The
accepted implementation in this file requires a one-digest amd64+arm64
manifest, a scratch seed image, and no `--platform` in `cli/cmd/seed.go`.
Master instead retains the amd64 image and explicit platform pins. The shipped
fix resolves the reported developer failure but does not meet those written
acceptance bullets.

## Reconciliation 2026-09-23

Classification: PARTIAL. Evidence: scratch multi-arch seed design/build only; not on master and no published manifest proof.

Remaining: Land and publish the multi-arch seed manifest, then prove arm64 consumption.

## Implementation 2026-09-23

Converted the seed shipping stage to `FROM scratch`, retaining only
`/seed.pg_dump`, `/seed.json`, and the OCI description label. Seed fetch no
longer pins pull or create to amd64; create supplies a never-run placeholder argv
because the scratch image has no command. Pull diagnostics now distinguish a
missing manifest from other Docker failures.

The Images workflow builds the payload once on amd64 and publishes an OCI index
whose amd64 and arm64 descriptors reference the same build output digest. The
published manifest and arm64 `./dev.sh build-sb` restore can only be proven by
the next Images run on a pushed commit, so status remains **In Progress**.
