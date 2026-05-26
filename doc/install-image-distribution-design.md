# Install / Upgrade image-distribution design

**Status:** draft for review (2026-05-26). Captures the decision to consolidate
the `sb` binary onto container-image distribution. Not yet implemented.

## Background — what we ship today

The StatBus codebase produces two parallel artifact streams for every
release:

1. **Per-service container images** built by `.github/workflows/images.yaml`
   on every push to `master` and on `workflow_dispatch`
   (`.github/workflows/images.yaml:15-24`). Four services — app, worker,
   db, proxy — are pushed to `ghcr.io/statisticsnorway/statbus-<service>`
   tagged `:<commit_short>-<arch>` for amd64 + arm64
   (`.github/workflows/images.yaml:88-91`). Layer-cache uses
   `type=registry,mode=max` with `cache-from + cache-to` pointing at
   `:buildcache-<arch>` (`.github/workflows/images.yaml:92-93`).

2. **A standalone `sb` binary** built by `.github/workflows/release.yaml`
   for four GOOS/GOARCH pairs (`.github/workflows/release.yaml:144-149`),
   published as `sb-{linux,darwin}-{amd64,arm64}` GitHub Release assets
   alongside `checksums.txt`, `release-manifest.json`, `seed.pg_dump`,
   `seed.json` (`.github/workflows/release.yaml:251-266`). The
   `release-manifest.json` carries BOTH the image refs (`images.{app,
   worker,db,proxy}:<commit_short>`) AND per-platform binary URLs in a
   `binaries[platform] = {url, sha256}` map
   (`.github/workflows/release.yaml:192-217`,
   `cli/internal/upgrade/github.go:43-53`).

Operator-facing entrypoints fetch the binary from the release asset URL:

- `install.sh` does `curl -fsSL "$BINARY_URL" -o ${HOME}/sb.tmp` where
  `$BINARY_URL` is the release asset URL constructed from `$VERSION`,
  `$OS`, `$ARCH` (`install.sh:193-199`).
- The upgrade-service does the symmetric thing via
  `replaceBinaryOnDisk(version)` in `cli/internal/upgrade/service.go:4584-4601`:
  it calls `FetchManifest(version)`, reads `manifest.Binaries[platform]`,
  and hands the URL + SHA256 to `selfupdate.ReplaceBinaryOnDisk`.

The seed database lives on a separate axis — per-commit git branches
`origin/seed/<commit_short>` populated by `./sb db seed sync`, fetched
during release.yaml's seed-publish step
(`.github/workflows/release.yaml:219-245`). The release tarball
republishes `seed.pg_dump` + `seed.json` as release assets, but the
git branch is the source of truth.

Image-cleanup keeps the last 20 untagged versions per service and
exempts tagged versions from deletion
(`.github/workflows/image-cleanup.yaml:20-25`), so any tagged image
stays on `ghcr.io` indefinitely.

## Motivation

Three pain points converge on "ship the sb binary as a container image":

1. **Per-commit testing is gated on release-tag ceremony.** The harness
   that proves install/upgrade recovery (`test/install-recovery/`) needs
   sb binaries built from arbitrary branch HEADs. Today the only place
   the binary is built is `release.yaml`, which fires on tag push (or
   manual dispatch with a tag). Branch HEADs have to be built locally
   (`./dev.sh build-sb`) and uploaded into each VM — the source of the
   "scenario-script-perms", "scenario-sb-swap-atomic", and
   "upload-sb-staleness" harness bugs (#165–167) from May 2026's
   harness arc.

2. **Offline install has three transport mechanisms.** A statistical
   office in Albania with intermittent internet has to fetch (a)
   container images via `docker pull`/registry, (b) the sb binary via
   `curl` from the GitHub release-asset URL, and (c) the seed via git
   over HTTPS. Each transport has its own failure mode. A
   "`docker save` → USB stick → `docker load`" workflow only works
   for one of the three today.

3. **The 166-RCs-to-8-releases inefficiency** (see
   `~/.claude-veridit/plans/recovery-injection-scope-a-comprehensive.md`,
   section "No-hotfix discipline"). Many of those RC cuts were
   driven by a need to produce a sb binary that some operator could
   pull from a release-asset URL. With the binary distributed as an
   image alongside everything else, branch-testing converges on the
   same artifact-procurement path as production install — same code
   path, same testing surface, no special-case "edge commit"
   procurement that builds from source (`buildBinaryOnDisk` at
   `cli/internal/upgrade/service.go:4623`).

## Target architecture

1. **New `statbus-sb` image.** Scratch base, contents = the four sb
   binaries + a tiny `entrypoint.sh`. Per-arch, per-commit-tagged
   like the existing four services. Built by `images.yaml` in the
   same matrix.

2. **Image-extract procurement.** `replaceBinaryOnDisk` in
   `cli/internal/upgrade/service.go:4584` becomes: `docker pull
   statbus-sb:<commit_short>` → `docker create` (no-run) → `docker cp`
   the per-platform binary out → SHA256 verify → atomic rename. Same
   ./sb.old rollback semantics. `install.sh:193-199` does the
   matching transformation: needs Docker present (already a hard
   prerequisite — `checkPrerequisites()` in `cli/cmd/install.go:2099`
   fails-fast if Docker isn't installed). No new system dependency.

3. **Release-asset binary kept during migration.** `release.yaml`
   continues publishing `sb-{linux,darwin}-{amd64,arm64}` until every
   live install has been upgraded to a sb that knows how to do
   image-extract procurement. Retired in step G of the migration
   sequence below.

4. **`workflow_dispatch` for branch builds.** Already present at
   `.github/workflows/images.yaml:24`. The comment block
   (`.github/workflows/images.yaml:18-23`) documents the existing
   design: tag-push is intentionally NOT a trigger because the
   master-push run for the same commit already produced the
   artifacts; `workflow_dispatch` is the "manual safety valve."
   Branch testing reuses this — `gh workflow run images.yaml --ref
   engineer/some-branch` produces commit-short-tagged images for the
   branch HEAD. **This part of the architecture is already in place.**

5. **`--version` accepts commit_short.** `install.sh` already
   distinguishes release-tag from commit-short via
   `versionRegex`/`IsCommitShort`
   (`cli/internal/upgrade/github.go:62-69`). The image-extract path
   needs no syntactic change — the image tag is the commit_short
   regardless of how the operator specified it.

6. **Seed stays on the git-branch axis.** Already per-commit-keyed
   via `seed/<commit_short>` and has its own preflight + lock
   discipline (`./sb db seed sync`). Moving it into a container image
   would duplicate that discipline without gain. Reconsider if/when
   the operator's offline workflow proves a uniform-transport
   benefit; not in this design's scope.

7. **Local-dev cache gap.** Local `docker buildx build` from a
   working tree that has diverged from any pushed branch won't get
   `cache-from` from ghcr.io's `:buildcache-<arch>` tag — cold
   layer rebuilds. Mitigation: a small `dev.sh` helper that wraps
   `buildx build --cache-from=type=registry,ref=...:buildcache-<arch>`.
   Documented; not a blocker.

8. **Uniform offline workflow.** Once `statbus-sb` is an image, the
   offline transport is single-mechanism: `docker save` of the five
   images (sb + four services), copied via removable media, `docker
   load` on the target. The seed remains a side-channel (git bundle
   over the same transport, or per-USB).

9. **Image-loss recovery.** `image-cleanup.yaml`'s `tagged-exempt`
   policy keeps per-commit-tagged images on ghcr.io indefinitely. If
   a tag is ever pruned (defensive thinking), `gh workflow run
   images.yaml --ref <tag-or-sha>` rebuilds from the git commit —
   source-of-truth is git, image is a derived cache.

## Migration sequence

Every step lands on master non-destructively; each runtime path
continues to work for installs that haven't yet been upgraded to the
sb that follows.

**A. Add `statbus-sb` image build to `images.yaml`.** New matrix entry
alongside app/worker/db/proxy. No consumer change. Cost: one more
parallel build per commit (~30 s cold, ~3 s warm with cache).

**B. (Already done.)** `workflow_dispatch` trigger exists at
`.github/workflows/images.yaml:24`. Skip.

**C. Extend `release-manifest.json` with image-procurement metadata
for sb.** Add `images.sb = "ghcr.io/.../statbus-sb:<commit_short>"`
to the manifest (`.github/workflows/release.yaml:192-217`) + add a
matching field to the Go-side `Manifest` struct
(`cli/internal/upgrade/github.go:43-53`). Doesn't change runtime
behavior; just publishes the new field.

**D. Teach `replaceBinaryOnDisk` + `install.sh` to PREFER image-extract,
fall back to release-asset.** Both paths supported simultaneously. New
installs on commits where the sb image exists use the new path;
installs of older versions whose manifest lacks `images.sb` continue
using the release-asset URL. No flag-day.

**E. Roll-forward through the existing release-asset path.** Every
live install (cloud slots, Albania, rune) takes one upgrade through
the OLD path (release-asset binary), which delivers a sb that has
image-extract logic. After this cycle, every live install runs sb
with the new procurement code.

**F. Verify in production that image-extract is being exercised.** Two
release cycles' worth of logs; confirm `replaceBinaryOnDisk` chose
the image path. The fallback should never fire for current commits.

**G. Stop publishing the release-asset binary.** Remove the binary
upload from `release.yaml:251-266` (keep checksums, manifest, seed).
Release-asset URL in old manifests still resolves (existing assets
aren't deleted retroactively), so any straggling old sb can still
self-update.

## Open questions

- **Seed-as-image versus git-branch.** Current design keeps git-branch.
  Worth revisiting after image-extract lands; uniformity gain may be
  worth the duplicated discipline.
- **Branch-image retention.** Image cleanup keeps tagged forever today.
  If `workflow_dispatch` from feature branches becomes common, that
  may need a TTL policy. Defer until usage data exists.
- **Edge-commit build-from-source.** `buildBinaryOnDisk` at
  `cli/internal/upgrade/service.go:4623` builds via `make -C cli build`
  for commits without release manifests. After image-extract lands,
  this could be replaced with a `workflow_dispatch`-pull path — but
  the build-from-source path also serves "operator's own fork" cases.
  Defer the retirement decision until usage data.
- **When to retire `replaceBinaryOnDisk`'s release-asset fallback.**
  Step F's verification window is "two release cycles"; that's a
  rough heuristic. May need a hard commit-min-version gate instead.

## Risks

- **Docker as hard dependency for binary self-update.** Already a hard
  dependency for install (`cli/cmd/install.go:2099-2110` fails-fast).
  No new system requirement. Risk: a corrupted Docker install blocks
  upgrade where the release-asset binary path would have worked. The
  fallback path in step D mitigates during migration; post-G, it's
  the operator's responsibility.
- **Image-extract failure paths multiplied.** `docker pull` can fail
  for network reasons, manifest signature reasons, registry-side
  outages. Each becomes a new failure surface that the upgrade state
  machine handles. Mitigation: SHA256 verify mirrors the existing
  selfupdate check; pull-fail surfaces a known error code so
  recoverFromFlag classifies the wedge correctly.
- **Build-from-source archival.** If ghcr.io ever fully fails (or
  Statistics Norway moves registries), the four service images and
  the new sb image must all be rebuildable from git. The
  `workflow_dispatch` path covers this — every artifact is derived
  from the git commit; nothing about the architecture creates a
  point where the registry IS the source of truth.

## Non-goals

- **Not changing image contents.** app/worker/db/proxy ship as today.
- **Not touching the upgrade state machine.** `executeUpgrade`,
  `applyPostSwap`, `recoverFromFlag` semantics are unchanged. Only
  the binary-procurement step (`replaceBinaryOnDisk`) shifts.
- **Not introducing new failure modes the harness doesn't cover.**
  The image-extract path is documented to fail-fast on pull error,
  SHA mismatch, or extract failure — each surfaces an
  ErrBinaryReplaceFailed that the existing rollback machinery
  handles. No new C-class entries in `inject.go`'s registry.
