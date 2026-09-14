---
id: STATBUS-367
title: >-
  statbus-seed image is amd64-only: arm64 developers never get the seed cache and are told the image does not exist
status: In Progress
assignee: []
created_date: '2026-09-14 10:14'
updated_date: '2026-09-14 13:47'
labels:
  - ci
  - dx
dependencies: []
priority: medium
type: bug
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
