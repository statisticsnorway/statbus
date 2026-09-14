---
id: STATBUS-367
title: >-
  statbus-seed image is amd64-only: arm64 developers never get the seed cache and are told the image does not exist
status: To Do
assignee: []
created_date: '2026-09-14 10:14'
updated_date: '2026-09-14 10:14'
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

## Fix (pick one, prefer the first)

- Pull-side pin: `sb db seed fetch` passes `--platform linux/amd64` on
  create/pull, since the image is data. One line in `cli/cmd/seed.go`.
- Or build-side: `platforms: linux/amd64,linux/arm64` on the seed job.
  Builds the same bytes twice; only worth it if `docker create` with a
  foreign platform proves awkward.

Either way: the fetch failure message must distinguish "manifest unknown"
(not built yet) from any other error, so the note in `dev.sh` and
`install.go` stops claiming the image does not exist when it does.

## Done when

`./dev.sh build-sb` on an arm64 Mac at a commit whose Images run is green
restores the seed (create-db logs one pg_restore, not 397 migrations). A
fetch at an unbuilt commit still prints the not-built note.
