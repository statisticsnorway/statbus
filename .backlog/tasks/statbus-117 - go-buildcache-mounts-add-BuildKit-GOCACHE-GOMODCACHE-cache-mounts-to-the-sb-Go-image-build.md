---
id: STATBUS-117
title: >-
  go-buildcache-mounts: add BuildKit GOCACHE/GOMODCACHE cache mounts to the sb
  Go image build
status: In Progress
assignee:
  - mechanic
created_date: '2026-06-30 16:48'
updated_date: '2026-06-30 20:11'
labels:
  - build-caching
  - performance
dependencies: []
priority: low
ordinal: 117000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Build-speed caching win, confirmed in the caching review (tmp/engineer-caching-review.md).

CREDIT — already optimal: the `sb` image's go.mod download IS cached as its own layer (go mod download before COPY source), so a source-only change does not re-download modules. Good.

THE GAP: there is NO BuildKit compile-cache mount, so every cli/ source change full-recompiles stdlib + deps (~1m). Adding `RUN --mount=type=cache,target=/root/.cache/go-build` (GOCACHE) and a GOMODCACHE mount to the build step makes the Go build cache persist across builds -> ~1m -> seconds.

IMPORTANT CAVEAT: type=cache mounts are NOT exported to the registry layer cache, and CI uses ephemeral runners -> CI will NOT benefit unless a persistent buildkit builder (or a cache-mount export mechanism) is configured. So this is primarily a LOCAL developer-loop win (which matters more if we keep a local test tier). Scope decision: the Dockerfile cache-mount is the easy part; the CI persistent-builder is a separate, optional follow-up.

Files: cli/Dockerfile.sb (the `sb` Go build). NOTE: the `worker` image (cli/Dockerfile) is CRYSTAL, not Go — different toolchain; out of scope here (its deps are already cached separately).
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 cli/Dockerfile.sb's Go build step uses a BuildKit `--mount=type=cache` for GOCACHE (and GOMODCACHE if not already covered by the download layer)
- [ ] #2 A local rebuild after a cli/ source-only change reuses the Go build cache (no stdlib/deps recompile) — measured ~1m -> seconds, recorded
- [ ] #3 The image still builds correctly cold (cache mount empty) and the produced sb binary is unchanged
- [ ] #4 The CI-runner caveat is documented in the task: type=cache is not registry-exported, so CI needs a persistent builder to benefit — flagged as a separate optional follow-up, not done here
<!-- AC:END -->
