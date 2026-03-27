# Upgrade System Guide

This guide covers operating the StatBus upgrade daemon on a standalone or private-mode server. It explains how upgrades are discovered, scheduled, executed, and rolled back.

## Overview

The upgrade daemon is a long-running process (`./sb upgrade daemon`) that:

- Polls GitHub Releases for new StatBus versions
- Pre-downloads Docker images so upgrades start instantly
- Listens for operator commands via PostgreSQL LISTEN/NOTIFY
- Executes upgrades with automatic database backup and rollback on failure
- Serves a maintenance page to users during the upgrade window
- Self-updates the `sb` binary after a successful upgrade

It is designed for remote servers where SSH access may be limited. Operators can trigger upgrades from the admin UI or the CLI, and the daemon handles the rest.

## Architecture

```
  GitHub Releases API          Admin UI (/admin/upgrades)
        |                              |
        v                              v
  +-----------+    LISTEN/NOTIFY   +----------+
  |  Daemon   |<-------------------| Database |
  |           |---(discover)------>|          |
  |           |---(status)-------->| upgrade  |
  +-----------+                    +----------+
        |
        |--- docker compose pull   (pre-download images)
        |--- git checkout vX.Y.Z   (switch code)
        |--- sb migrate up         (apply migrations)
        |--- docker compose up -d  (start services)
        |--- health check          (verify success)
```

**Key design decisions:**

- **Advisory lock** prevents multiple daemon instances from running simultaneously.
- **Database-backed state** in the `public.upgrade` table means the daemon can restart without losing track of pending upgrades.
- **File-based maintenance mode** (`~/statbus-maintenance/active`) lets Caddy serve the maintenance page without any daemon involvement during the actual downtime window.
- **Stale maintenance cleanup** on daemon startup removes leftover maintenance files from interrupted upgrades.

## Configuration

Edit `.env.config` and run `./sb config generate` to apply changes.

| Key | Default | Description |
|-----|---------|-------------|
| `UPGRADE_CHANNEL` | `stable` | Which releases to discover: `stable` (non-prerelease only), `prerelease` (all releases), `edge` (every master commit), or `pinned` (no discovery). |
| `UPGRADE_CHECK_INTERVAL` | `6h` | How often the daemon polls GitHub. Any Go duration string (`30m`, `6h`, `24h`). |
| `UPGRADE_AUTO_DOWNLOAD` | `true` | Pre-download Docker images for discovered releases. Set to `false` on metered connections. |
| `UPGRADE_PINNED_VERSION` | *(empty)* | When channel is `pinned`, this version is the only one the daemon will accept. |

The `GITHUB_TOKEN` environment variable is optional but recommended. Without it, the GitHub API allows 60 requests/hour; with it, 5000 requests/hour. Set it in the systemd unit override or in the shell environment.

## Edge Upgrade Channel

The `edge` channel tracks every commit pushed to the `master` branch, not just tagged releases. It is intended for development and testing servers where you want to stay on the latest code at all times.

**How it works:**

- CI builds and pushes Docker images for every master commit, tagged with the commit SHA (e.g., `ghcr.io/statisticsnorway/statbus-app:sha-abc1234f`).
- The daemon discovers new commits by polling the GitHub API for the latest master HEAD.
- When a new commit is found, the daemon auto-schedules it for immediate upgrade -- no operator action required.
- Upgrades use the same lifecycle as tagged releases (backup, checkout, migrate, restart, health check, rollback on failure).

**Enable the edge channel:**

```bash
./sb dotenv -f .env.config set UPGRADE_CHANNEL edge
./sb config generate
```

Then restart the daemon (or start it if not running):

```bash
sudo systemctl restart statbus-upgrade@statbus_no
```

**Important considerations:**

- **Development/testing only.** Edge upgrades are not suitable for production. Every master commit is deployed without manual review.
- **High churn.** The daemon will upgrade on every push to master. Set `UPGRADE_CHECK_INTERVAL` to control how frequently it polls (default `6h`; for active development, `15m` or `30m` may be appropriate).
- **Migrations may be untested.** Edge commits may include migrations that have not been validated in a full release cycle.
- **Version format.** Edge versions use `sha-HEXHEX` format (e.g., `sha-abc1234f`) instead of `vYYYY.MM.PATCH`.

## Operating the Daemon

### systemd (recommended for production)

The unit file is at `devops/statbus-upgrade.service`. It uses a template (`%i`) so each deployment slot gets its own instance.

Install and enable:

```bash
sudo cp devops/statbus-upgrade.service /etc/systemd/system/statbus-upgrade@.service
sudo systemctl daemon-reload
sudo systemctl enable --now statbus-upgrade@statbus_no
```

View logs:

```bash
sudo journalctl -u statbus-upgrade@statbus_no -f
```

The service restarts automatically on failure (`Restart=always`, `RestartSec=30`). Exit code 42 signals a binary self-update -- systemd treats it as a success (`SuccessExitStatus=42`) and restarts the daemon with the new binary.

### CLI commands

```bash
# Check GitHub for releases (one-shot, does not require the daemon)
./sb upgrade check

# List upgrades tracked in the database
./sb upgrade list

# Schedule an upgrade (daemon picks it up on next tick)
./sb upgrade schedule v2026.03.1

# Trigger immediate upgrade via NOTIFY (daemon executes within seconds)
./sb upgrade apply v2026.03.1

# Trigger upgrade with full database recreate instead of migrations
./sb upgrade apply v2026.03.1 --recreate

# Run the daemon in the foreground (for debugging)
./sb upgrade daemon
./sb upgrade daemon --verbose
```

Version format: `vYYYY.MM.PATCH` (e.g., `v2026.03.1`) or `sha-HEXHEX` (e.g., `sha-abc1234f`).

### Database recreate (`--recreate`)

The `--recreate` flag tells the daemon to destroy and recreate the database from scratch instead of running incremental migrations. The full migration history is applied to a fresh database.

```bash
./sb upgrade apply v2026.03.1 --recreate
```

**When to use:**

- Development or demo servers where data is disposable.
- When migrations have accumulated to the point where a fresh start is cleaner.
- When a migration bug makes incremental upgrade impossible.

**What happens:**

The upgrade follows the same lifecycle as a normal upgrade (steps 1-19 in the table above), except step 13 replaces `sb migrate up` with a full database recreate (`delete-db` + `create-db`). All existing data is destroyed. The rsync backup is still taken before the recreate (step 6), so automatic rollback works: if the recreate or any subsequent step fails, the daemon restores the backed-up database volume.

**This flag is destructive.** Never use it on a production server with real data. It is intended for dev/demo environments only.

### Admin UI

Navigate to `/admin/upgrades` in the StatBus web interface. The page shows all discovered upgrades with their status and provides buttons to:

- **Upgrade Now** -- schedules immediate execution (with confirmation dialog)
- **Unschedule** -- cancels a pending scheduled upgrade
- **Retry** -- resets a failed/rolled-back upgrade for re-execution
- **Skip** -- marks a version as skipped so it won't be retried
- **Report Issue** -- opens a pre-filled GitHub issue for failed upgrades

The page auto-refreshes every 30 seconds. Upgrades with database migrations are flagged with a database icon.

## Upgrade Lifecycle

When the daemon executes an upgrade, it follows these steps in order. If any step fails, the daemon rolls back automatically (see Rollback below).

| Step | Action | Detail |
|------|--------|--------|
| 1 | Pull images | `docker compose pull` with the target VERSION |
| 2 | Close DB connection | Daemon disconnects from PostgreSQL |
| 3 | Maintenance mode ON | Creates `~/statbus-maintenance/active` |
| 4 | Stop app/worker/rest | `docker compose stop app worker rest` |
| 5 | Stop database | `docker compose stop db` |
| 6 | Backup database | `sudo rsync -a --delete` of `postgres/volumes/db/data/` to `~/statbus-backups/pre-upgrade/` |
| 7 | Git checkout | `git fetch --tags --depth 1 origin tag vX.Y.Z && git checkout vX.Y.Z` |
| 7b | Verify tag SHA | Compares checked-out HEAD against `release-manifest.json` commit SHA |
| 8 | Regenerate config | `./sb config generate` |
| 9 | Pull updated images | `docker compose pull` (with new VERSION from regenerated .env) |
| 10 | Start database | `docker compose up -d db` |
| 11 | Wait for DB health | `pg_isready` check, 30 second timeout |
| 12 | Reconnect daemon | Re-establishes DB connection and advisory lock |
| 13 | Run migrations | `./sb migrate up --verbose` |
| 14 | Start all services | `docker compose up -d --remove-orphans` |
| 15 | Health check | HTTP GET to the app, 5 retries at 5 second intervals |
| 16 | Maintenance mode OFF | Removes `~/statbus-maintenance/active` |
| 17 | Archive backup | Compresses backup to `~/statbus-backups/vX.Y.Z-pre.tar.gz` |
| 18 | Mark complete | Sets `completed_at` in the upgrade table |
| 19 | Self-update | Downloads new `sb` binary from release manifest, verifies SHA256, exits with code 42 for systemd restart |

## Rollback

### Automatic rollback on failure

If any step from 7 onward fails, the daemon automatically:

1. Stops all services (`docker compose stop app worker rest db`)
2. Restores git to the previous version (`git checkout -f <previous_version>`)
3. Regenerates config (`./sb config generate`)
4. Restores the database backup via `sudo rsync -a --delete` from `~/statbus-backups/pre-upgrade/`
5. Starts all services (`docker compose up -d --remove-orphans`)
6. Reconnects to the database
7. Deactivates maintenance mode
8. Records `error` and `rollback_completed_at` in the upgrade table

### Manual binary rollback

If the `sb` binary self-update causes problems:

```bash
# Roll back to the previous sb binary (saved as sb.old)
./sb upgrade self-rollback
```

### Retrying after a rollback

From the CLI:

```bash
# Reset the upgrade for re-execution
echo "UPDATE public.upgrade SET started_at = NULL, error = NULL, rollback_completed_at = NULL, scheduled_at = now() WHERE version = 'v2026.03.1'" | ./sb psql
```

Or use the **Retry** button in the admin UI at `/admin/upgrades`.

## Maintenance Mode

During an upgrade, users see a maintenance page instead of the application.

**How it works:**

1. The daemon creates `~/statbus-maintenance/active` (a plain text file).
2. Caddy checks for this file on every request via a `file` matcher in the Caddyfile.
3. If the file exists, Caddy serves `devops/maintenance/maintenance.html` with HTTP 503.
4. The `/upgrade-progress.log` path is excluded from maintenance mode -- Caddy serves `tmp/upgrade-progress.log` so the maintenance page can show live progress.
5. The maintenance page auto-refreshes every 5 seconds and checks if the app is back. Once it gets a non-503 response, it redirects the user automatically.
6. If the upgrade takes longer than 10 minutes, the maintenance page shows a warning.

**Volume mounts** in `caddy/docker-compose.yml` that enable this:

```yaml
volumes:
  - ${HOME}/statbus-maintenance:/statbus-maintenance:ro   # Active file
  - ../devops/maintenance:/maintenance-page:ro            # HTML page
  - ../tmp:/statbus-tmp:ro                                # Progress log
```

**Stale cleanup:** On startup, the daemon checks if a maintenance file exists but no upgrade is actually in progress. If so, it removes the file.

## Database Tracking

### `public.upgrade` table

Tracks the full lifecycle of every discovered release.

| Column | Type | Description |
|--------|------|-------------|
| `id` | `integer` | Auto-generated primary key |
| `version` | `text` | Release tag (e.g., `v2026.03.1`), unique |
| `commit_sha` | `text` | Git commit SHA from release manifest |
| `is_prerelease` | `boolean` | Whether this is a pre-release |
| `summary` | `text` | Release title |
| `changes` | `text` | Full release body / changelog |
| `release_url` | `text` | GitHub release page URL |
| `has_migrations` | `boolean` | Whether the release includes database migrations |
| `from_version` | `text` | Version the server was running before this upgrade started |
| `discovered_at` | `timestamptz` | When the daemon first saw this release |
| `scheduled_at` | `timestamptz` | When this upgrade was scheduled (set by operator or daemon) |
| `started_at` | `timestamptz` | When execution began |
| `completed_at` | `timestamptz` | When the upgrade finished successfully |
| `error` | `text` | Error message if the upgrade failed |
| `rollback_completed_at` | `timestamptz` | When rollback finished (only if `error` is set) |
| `skipped_at` | `timestamptz` | When the operator chose to skip this version |
| `images_downloaded` | `boolean` | Whether Docker images have been pre-downloaded |
| `backup_path` | `text` | Filesystem path to the pre-upgrade database backup |

**Lifecycle constraint:** The table enforces a CHECK constraint ensuring valid state transitions:
- `completed_at` requires `started_at`
- `started_at` requires `scheduled_at`
- Cannot be both skipped and completed
- `rollback_completed_at` requires `error`
- Cannot be both completed and have an error
- Cannot be both completed and rolled back

**RLS policies:** `admin_user` has full access; `authenticated` has read-only access.

### `public.system_info` table

Key-value store for system-wide settings.

| Key | Default | Description |
|-----|---------|-------------|
| `upgrade_channel` | `stable` | Current upgrade channel |
| `upgrade_check_interval` | `6h` | Check interval |
| `upgrade_auto_download` | `true` | Auto-download setting |

The daemon reads configuration from `.env` (generated from `.env.config`), not from this table. The table provides visibility into the current settings from the admin UI.

### Release manifest

Each GitHub release includes a `release-manifest.json` asset with:

```json
{
  "version": "v2026.03.1",
  "commit_sha": "abc123def456...",
  "prerelease": false,
  "has_migrations": true,
  "images": { "app": "ghcr.io/statisticsnorway/statbus-app:v2026.03.1" },
  "binaries": {
    "linux-amd64": { "url": "https://...", "sha256": "..." },
    "linux-arm64": { "url": "https://...", "sha256": "..." }
  }
}
```

The daemon uses the manifest to verify the git checkout SHA (detecting tag spoofing) and to find the correct `sb` binary for self-update.

## Troubleshooting

### Daemon won't start: "another upgrade daemon is already running"

The daemon acquires a PostgreSQL advisory lock (`pg_try_advisory_lock(hashtext('upgrade_daemon'))`). If a previous instance crashed without releasing it, the lock is automatically freed when the database connection closes. Check for stale connections:

```bash
echo "SELECT pid, state, query FROM pg_stat_activity WHERE application_name = 'statbus-upgrade-daemon'" | ./sb psql
```

If the connection is gone but the error persists, restart the database container:

```bash
docker compose restart db
```

### Upgrade stuck in "in progress"

Check the progress log:

```bash
cat tmp/upgrade-progress.log
```

If the daemon crashed mid-upgrade, the maintenance file may be stale. The daemon cleans it automatically on next startup. To clean manually:

```bash
rm ~/statbus-maintenance/active
```

### GitHub rate limiting

Without `GITHUB_TOKEN`, the API allows only 60 requests/hour. The daemon fetches up to 30 releases per check. Set a token:

```bash
# In systemd override
sudo systemctl edit statbus-upgrade@statbus_no
# Add:
# [Service]
# Environment=GITHUB_TOKEN=ghp_xxxxxxxxxxxxx
```

### Health check fails after upgrade

The daemon retries the health check 5 times at 5-second intervals. If it still fails, the upgrade is rolled back. Common causes:

- The new version has a startup bug -- check `docker compose logs app`
- Port configuration changed -- verify `.env` has the correct `CADDY_HTTP_PORT`
- Database migrations failed silently -- check `docker compose logs db`

### Pre-download fills disk

Docker images accumulate. The daemon does not prune old images, only old backup archives (keeps the 3 most recent). Clean up manually:

```bash
docker image prune -a --filter "until=720h"   # Remove images older than 30 days
```

### Self-update failed

If the `sb` binary update fails, the error is recorded in `public.system_info` under the key `self_update_error`. The previous binary is preserved as `sb.old`:

```bash
# Check the error
echo "SELECT value FROM public.system_info WHERE key = 'self_update_error'" | ./sb psql

# Roll back to previous binary
./sb upgrade self-rollback
```

### Testing rollback

To verify the rollback path works without ruining a release, create a sentinel file before triggering an upgrade:

```bash
touch tmp/simulate-upgrade-failure
./sb upgrade apply <version>
```

The daemon runs the full upgrade (pull, backup, checkout, migrate, restart, health check) and then sees the sentinel file, deletes it, and triggers a complete rollback. The upgrade row will show `error = "simulated upgrade failure for rollback testing"` and `rollback_completed_at` is set.

The sentinel is consumed automatically. To upgrade for real, just trigger the upgrade again without the file.

### Database backup/restore requires sudo

The database data directory is owned by the postgres container user. The daemon uses `sudo rsync` for backup and restore. Ensure the service user has passwordless sudo for rsync:

```bash
# /etc/sudoers.d/statbus-backup
statbus_no ALL=(ALL) NOPASSWD: /usr/bin/rsync
```

### Backup archive retention

After each successful upgrade, the pre-upgrade backup is compressed to `~/statbus-backups/<version>-pre.tar.gz`. The daemon keeps the 3 most recent archives and deletes older ones automatically.
