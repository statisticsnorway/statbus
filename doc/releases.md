# Release Pipeline Guide

How StatBus releases are built, published, and deployed.

## Versioning

StatBus uses **Calendar Versioning (CalVer)**: `YYYY.MM.PATCH`.

| Format | Example | Meaning |
|--------|---------|---------|
| Stable | `v2026.03.0` | First stable release of March 2026 |
| Patch | `v2026.03.1` | Patch to the March 2026 release |
| Release candidate | `v2026.03.0-rc.01` | Pre-release for testing |
| Beta | `v2026.03.0-beta.01` | Early pre-release |

**Zero-pad pre-release numbers** to two digits (`rc.01`, not `rc.1`). GitHub sorts releases lexicographically, so `rc.6` would sort after `rc.22` without padding.

Tags must start with `v`. The version **without** the `v` prefix (e.g. `2026.03.0`) is used in image tags, the `VERSION` env var, and the release manifest.

Pre-release detection: the release workflow checks if the tag matches `-(rc|beta|alpha)\.` and marks the GitHub Release accordingly.

## How to Cut a Release

### Stable release

```bash
git tag v2026.03.0
git push origin v2026.03.0
```

### Pre-release

```bash
git tag v2026.03.0-rc.01
git push origin v2026.03.0-rc.01
```

That is it. Pushing a `v*` tag triggers the `release.yaml` workflow, which builds everything and creates the GitHub Release automatically.

### What happens automatically

1. Four Docker images are built and pushed to `ghcr.io` (app, worker, db, proxy).
2. Four cross-platform `sb` binaries are compiled (linux/amd64, linux/arm64, darwin/amd64, darwin/arm64).
3. A `release-manifest.json` is generated with image references, binary URLs, SHA-256 checksums, and migration metadata.
4. A GitHub Release is created with auto-generated notes, all binaries, checksums, and the manifest attached.

## Release Workflow Details

The workflow (`.github/workflows/release.yaml`) runs three sequential jobs.

### Job 1: `build-images`

Runs a matrix of four services in parallel:

| Service | Build context | Dockerfile |
|---------|--------------|------------|
| `app` | `./app` | `./app/Dockerfile` |
| `worker` | `./cli` | `./cli/Dockerfile` |
| `db` | `./postgres` | `./postgres/Dockerfile` |
| `proxy` | `./caddy` | `./caddy/Dockerfile` |

Each image is pushed with two tags:
- `sha-<8-char-commit-sha>` (immutable content address)
- `<version-tag>` (e.g. `v2026.03.0`)

Outputs: `sha`, `sha_tag`, `version_tag`, `version`, `prerelease`.

### Job 2: `build-binaries`

Cross-compiles the Go CLI for four platforms:

```
linux/amd64   linux/arm64   darwin/amd64   darwin/arm64
```

Binaries are named `sb-<os>-<arch>` and built with `CGO_ENABLED=0` and ldflags embedding the version and commit SHA. SHA-256 checksums are computed into `checksums.txt`.

### Job 3: `create-release`

1. **Migration detection**: Compares `migrations/*.up.sql` and `migrations/*.up.psql` between the current tag and the previous tag. Sets `has_migrations=true` if any were added.
2. **Manifest generation**: Writes `release-manifest.json` containing:
   - `version`, `commit_sha`, `prerelease`, `has_migrations`
   - `images`: full `ghcr.io` paths for all four services
   - `binaries`: download URLs and SHA-256 hashes for all four platforms
3. **GitHub Release**: Created via `gh release create` with `--generate-notes`. Pre-release tags get the `--prerelease` flag.

## CI Images

The `ci-images.yaml` workflow builds SHA-tagged images on every push to `master`.

- **Trigger**: push to `master` branch
- **Images built**: same four services (app, worker, db, proxy)
- **Tag format**: `sha-<full-40-char-commit-sha>`
- **Purpose**: cloud deployments pull these images instead of building on each host

These images are used by the branch-based deploy workflows (`deploy-to-*.yaml`) and the upgrade service for SHA-based deployments.

## Image Cleanup

The `image-cleanup.yaml` workflow runs weekly to remove old images.

- **Schedule**: Sunday 4:00 AM UTC (also supports manual trigger)
- **Retention**: keeps the 20 most recent versions per package
- **Scope**: only deletes **untagged** versions (version-tagged images like `v2026.03.0` are kept indefinitely)
- **Packages cleaned**: `statbus-app`, `statbus-worker`, `statbus-db`, `statbus-proxy`

## Image Registry Layout

All images are in the GitHub Container Registry under `ghcr.io/statisticsnorway/`:

```
ghcr.io/statisticsnorway/statbus-app:<tag>
ghcr.io/statisticsnorway/statbus-worker:<tag>
ghcr.io/statisticsnorway/statbus-db:<tag>
ghcr.io/statisticsnorway/statbus-proxy:<tag>
```

### Tag naming

| Tag pattern | Source | Example |
|-------------|--------|---------|
| `v2026.03.0` | Release workflow (tag push) | Stable release |
| `v2026.03.0-rc.1` | Release workflow (tag push) | Pre-release |
| `sha-abc1234f` | Release workflow (tag push) | 8-char SHA, alongside version tag |
| `sha-<40-char>` | CI workflow (master push) | Full SHA for cloud deploys |
| `local` | Local `docker compose build` | Default when `VERSION` is unset |

Docker Compose files reference images as:

```yaml
image: ghcr.io/statisticsnorway/statbus-app:${VERSION:-local}
```

When `VERSION` is set (via `.env`), containers pull the pre-built image. When unset, they build locally.

## Testing a Pre-Release

### 1. Tag and push

```bash
git tag v2026.03.0-rc.1
git push origin v2026.03.0-rc.1
```

Wait for the release workflow to complete in GitHub Actions.

### 2. Deploy to a test server via the upgrade service

Use the **Deploy via upgrade service** workflow (`.github/workflows/deploy-via-upgrade.yaml`) from the GitHub Actions UI:

- **Target**: select the server.
  - Multi-tenant cloud slot: `statbus_<slot>@niue.statbus.org` (e.g. `statbus_dev@niue.statbus.org`).
  - Standalone box: `devops@<host>.statbus.org` (e.g. `statbus@rune.statbus.org` for Norway).
- **Version**: enter the tag (e.g. `v2026.03.0-rc.1`)
- **Action**: `apply`

This SSHs to the server and sends a PostgreSQL NOTIFY:

```sql
NOTIFY upgrade_apply, 'v2026.03.0-rc.1';
```

The upgrade service on the server handles the rest: pull images, stop services, backup database, checkout tag, run migrations, restart, health check.

### 3. Or deploy manually via SSH

```bash
# Multi-tenant slot on niue
ssh statbus_dev@niue.statbus.org "cd statbus && echo \"NOTIFY upgrade_apply, 'v2026.03.0-rc.1';\" | ./sb psql"

# Standalone box (e.g. rune for Norway)
ssh statbus@rune.statbus.org   "cd statbus && echo \"NOTIFY upgrade_apply, 'v2026.03.0-rc.1';\" | ./sb psql"
```

### 4. Verify

```bash
ssh statbus_dev@niue.statbus.org "cd statbus && ./sb version"
ssh statbus@rune.statbus.org      "cd statbus && ./sb version"
```

### Upgrade channels

The upgrade service's behavior depends on the `UPGRADE_CHANNEL` setting in `.env`:

| Channel | Behavior |
|---------|----------|
| `stable` (default) | Only discovers non-prerelease releases |
| `prerelease` | Discovers all releases including rc/beta/alpha |
| `edge` | Discovers every commit pushed to `master` |

To target a specific version for a one-off upgrade (e.g. pin or downgrade), use `./sb upgrade schedule <version>` or an explicit `NOTIFY upgrade_apply` — both bypass channel filtering.

## Release Manifest

Each release includes a `release-manifest.json` that the upgrade service downloads to verify deployments. Structure:

```json
{
  "version": "2026.03.0",
  "commit_sha": "abc123...",
  "prerelease": false,
  "has_migrations": true,
  "images": {
    "app": "ghcr.io/statisticsnorway/statbus-app:v2026.03.0",
    "db": "ghcr.io/statisticsnorway/statbus-db:v2026.03.0",
    "worker": "ghcr.io/statisticsnorway/statbus-worker:v2026.03.0",
    "proxy": "ghcr.io/statisticsnorway/statbus-proxy:v2026.03.0"
  },
  "binaries": {
    "linux-amd64": { "url": "https://github.com/.../sb-linux-amd64", "sha256": "..." },
    "linux-arm64": { "url": "https://github.com/.../sb-linux-arm64", "sha256": "..." },
    "darwin-amd64": { "url": "https://github.com/.../sb-darwin-amd64", "sha256": "..." },
    "darwin-arm64": { "url": "https://github.com/.../sb-darwin-arm64", "sha256": "..." }
  }
}
```

The service uses the manifest to:
- Verify the git checkout SHA matches `commit_sha` (detects tag spoofing)
- Determine if migrations are needed (`has_migrations`)
- Download the correct `sb` binary for self-update after a successful upgrade
