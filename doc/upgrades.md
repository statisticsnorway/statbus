# Upgrade System Guide

This guide covers operating the StatBus upgrade service on a standalone or private-mode server. It explains how upgrades are discovered, scheduled, executed, and rolled back.

## Overview

The upgrade service is a long-running process (`./sb upgrade service`) that:

- Polls GitHub Releases for new StatBus versions
- Pre-downloads Docker images so upgrades start instantly
- Listens for operator commands via PostgreSQL LISTEN/NOTIFY
- Executes upgrades with an automatic pre-upgrade database snapshot, a read-only window over the destructive phase, and classify-then-act recovery (data-safe rollback where the box is behind target; a PARK that waits for a fix release where it is at target)
- Serves a maintenance page to users during the upgrade window
- Self-updates the `sb` binary after a successful upgrade

It is designed for remote servers where SSH access may be limited. Operators can trigger upgrades from the admin UI or the CLI, and the upgrade service handles the rest.

## Architecture

```
  GitHub Releases API          Admin UI (/admin/upgrades)
        |                              |
        v                              v
  +-----------+    LISTEN/NOTIFY   +----------+
  | Service  |<-------------------| Database |
  |          |---(discover)------>|          |
  |          |---(status)-------->| upgrade  |
  +----------+                    +----------+
        |
        |--- docker compose pull   (pre-download images)
        |--- git checkout vX.Y.Z   (switch code)
        |--- sb migrate up         (apply migrations)
        |--- docker compose up -d  (start services)
        |--- health check          (verify success)
```

**Key design decisions:**

- **Advisory lock** prevents multiple service instances from running simultaneously.
- **Database-backed state** in the `public.upgrade` table means the service can restart without losing track of pending upgrades.
- **File-based maintenance mode** (`~/statbus-maintenance/active`) lets Caddy serve the maintenance page without any service involvement during the actual downtime window.
- **Stale maintenance cleanup** on service startup removes leftover maintenance files from interrupted upgrades.

## Configuration

Edit `.env.config` and run `./sb config generate` to apply changes.

| Key | Default | Description |
|-----|---------|-------------|
| `UPGRADE_CHANNEL` | `stable` | Which releases to discover: `stable` (non-prerelease only), `prerelease` (all releases), or `edge` (every master commit). To target a specific version for a one-off upgrade, use `./sb upgrade register <version>` then `./sb upgrade schedule <version>` instead. |
| `UPGRADE_CHECK_INTERVAL` | `6h` | How often the service polls GitHub. Any Go duration string (`30m`, `6h`, `24h`). |
| `UPGRADE_AUTO_DOWNLOAD` | `true` | Pre-download Docker images for discovered releases. Set to `false` on metered connections. |

The `GITHUB_TOKEN` environment variable is optional but recommended. Without it, the GitHub API allows 60 requests/hour; with it, 5000 requests/hour. Set it in the systemd unit override or in the shell environment.

## Edge Upgrade Channel

The `edge` channel tracks every commit pushed to the `master` branch, not just tagged releases. It is intended for development and testing servers where you want to stay on the latest code at all times.

**How it works:**

- CI builds and pushes Docker images for every master commit, tagged with the 8-char commit_short (rc.63: `ghcr.io/statisticsnorway/statbus-app:abc1234f`).
- The service discovers new commits by polling the GitHub API for the latest master HEAD.
- When a new commit is found, the service auto-schedules it for immediate upgrade -- no operator action required.
- Upgrades use the same lifecycle as tagged releases (backup, checkout, migrate, restart, health check, rollback on failure).

**Enable the edge channel:**

```bash
./sb dotenv -f .env.config set UPGRADE_CHANNEL edge
./sb config generate
```

Then restart the service (or start it if not running):

```bash
sudo systemctl restart statbus-upgrade@statbus_no
```

**Important considerations:**

- **Development/testing only.** Edge upgrades are not suitable for production. Every master commit is deployed without manual review.
- **High churn.** The service will upgrade on every push to master. Set `UPGRADE_CHECK_INTERVAL` to control how frequently it polls (default `6h`; for active development, `15m` or `30m` may be appropriate).
- **Migrations may be untested.** Edge commits may include migrations that have not been validated in a full release cycle.
- **Version format.** Edge versions use the bare 8-char `commit_short` (e.g., `abc1234f`) instead of `vYYYY.MM.PATCH`. Rc.63 canonical naming — no `sha-` prefix.

## Operating the Service

### systemd (recommended for production)

The unit file is at `ops/statbus-upgrade.service`. It uses a template (`%i`) so each deployment slot gets its own instance.

Install and enable:

```bash
sudo cp ops/statbus-upgrade.service /etc/systemd/system/statbus-upgrade@.service
sudo systemctl daemon-reload
sudo systemctl enable --now statbus-upgrade@statbus_no
```

View logs:

```bash
sudo journalctl -u statbus-upgrade@statbus_no -f
```

The service restarts automatically on failure (`Restart=always`, `RestartSec=30`). Exit code 42 signals a binary self-update -- systemd treats it as a success (`SuccessExitStatus=42`) and restarts the service with the new binary.

### CLI commands

```bash
# Fetch GitHub releases and register them as candidates (one-shot, no service needed)
./sb upgrade check

# List registered upgrade candidates and their status
./sb upgrade list

# Register a specific release tag or commit as a candidate (prerequisite for schedule)
./sb upgrade register v2026.03.1

# Queue an already-registered candidate to run (the service executes it within
# seconds of the scheduling NOTIFY)
./sb upgrade schedule v2026.03.1

# Queue an upgrade with a full database recreate instead of migrations
./sb upgrade schedule v2026.03.1 --recreate

# Run the upgrade service in the foreground (for debugging)
./sb upgrade service
./sb upgrade service --verbose

# Dispatch a scheduled upgrade inline without going through the service
# (useful when the service is stopped or you want to run the upgrade
# in the current shell for debugging).
./sb install
```

`./sb install` is the unified entrypoint. When a scheduled row exists it claims it atomically and runs the same pipeline the service uses (backup, checkout, migrate, restart, health-check, rollback on failure). If the service unit is active, it gets restarted at the end so it picks up the new binary. See `doc/upgrade-timeline.md` for the full state-detection ladder.

Version format: `vYYYY.MM.PATCH` (e.g., `v2026.03.1`) or 8-char `commit_short` (e.g., `abc1234f`).

### Database recreate (`--recreate`)

The `--recreate` flag tells the upgrade service to destroy and recreate the database from scratch instead of running incremental migrations. The full migration history is applied to a fresh database.

```bash
./sb upgrade register v2026.03.1
./sb upgrade schedule v2026.03.1 --recreate
```

**When to use:**

- Development or demo servers where data is disposable.
- When migrations have accumulated to the point where a fresh start is cleaner.
- When a migration bug makes incremental upgrade impossible.

**What happens:**

The upgrade follows the same lifecycle as a normal upgrade (steps 1-19 in the table above), except step 13 replaces `sb migrate up` with a full database recreate (`delete-db` + `create-db`). All existing data is destroyed. The rsync backup is still taken before the recreate (step 6), so automatic rollback works: if the recreate or any subsequent step fails, the service restores the backed-up database volume.

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

An upgrade runs in two halves split by a binary swap — the OLD binary does the safe preparation and the destructive pre-swap steps, then hands off; the NEW binary's process finishes the pipeline. In outline (the step-by-step walkthrough with every gate is `doc/upgrade-timeline.md`; the decision logic is `doc/upgrade-recovery-model.md`):

1. **Pre-flight** (no marker yet) -- downgrade/platform/disk/signature checks; reject cleanly before anything destructive.
2. **Marker + warm-up** -- the `upgrade-in-progress` marker is written (from here a crash is resumable); images pre-pulled.
3. **Read-only window ON** -- external writes are blocked for the destructive phase (an accident-guard; `doc/read-only-upgrade-window.md`). Maintenance page ON; app/worker/rest stopped; **database stopped**.
4. **Snapshot** -- the stopped volume is rsync'd to `~/statbus-backups/pre-upgrade-active/` (atomic dir-rename commit; this is the rollback artifact).
5. **Fetch + binary swap** -- the target's git objects are fetched (no checkout yet), the new `./sb` lands on disk, and the process exits so the NEW binary takes over.
6. **New binary's pipeline** -- checkout of the exact target, boot migration of the daemon's own small floor only, then the guarded resume: the upgrade's migration delta applies exactly once, services start, the health check must pass, maintenance OFF, the row reaches `completed`, and the read-only window lifts.

There is no post-completion archive step -- the forensic tar was removed (the persistent snapshot dir is the single backup artifact).

## Rollback

### What happens on failure -- classify, then act

A failed step is classified before anything acts (`doc/upgrade-recovery-model.md`):

- **Transient** (recognized: DB unreachable, fetch stall) -- retried in-process with backoff; if it clears, the upgrade continues; if it exhausts, it is treated as no-longer-transient.
- **Deterministic, box BEHIND the target** -- automatic **rollback**: git and config restored to the previous version, the database restored from the pre-upgrade snapshot, services restarted, `rolled_back_at` + `error` recorded. The read-only window guarantees the restore loses no external data.
- **Deterministic, box AT the target** (e.g. the new version cannot pass its health check) -- the upgrade **PARKS** instead of rolling back: the row stays `in_progress` with `recovery_parked_at` set, the box stays up and idle (no crash loop), and one alert fires. A parked upgrade resolves when you schedule a fix release (its claim displaces the park) or run the install entrypoint for one fresh attempt.
- **Unknown** -- the service stops loudly and waits for a person; it neither retries nor rolls back on an error it cannot name.

### Manual binary rollback

If the `sb` binary self-update causes problems:

```bash
# Roll back to the previous sb binary (saved as sb.old)
./sb upgrade self-rollback
```

### Retrying after a rollback

Re-dispatch through the normal scheduling path -- never by editing the table by hand:

```bash
./sb upgrade schedule v2026.03.1
```

`schedule` atomically resets the row (including any park marker) and queues it; the service claims it on its next tick, or run the install entrypoint to dispatch immediately. The **Retry** button in the admin UI at `/admin/upgrades` does the same thing.

## Maintenance Mode

During an upgrade, users see a maintenance page instead of the application.

**How it works:**

1. The upgrade service creates `~/statbus-maintenance/active` (a plain text file).
2. Caddy checks for this file on every request via a `file` matcher in the Caddyfile.
3. If the file exists, Caddy serves `ops/maintenance/maintenance.html` with HTTP 503.
4. The `/upgrade-progress.log` path is excluded from maintenance mode -- Caddy serves `tmp/upgrade-progress.log` so the maintenance page can show live progress.
5. The maintenance page auto-refreshes every 5 seconds and checks if the app is back. Once it gets a non-503 response, it redirects the user automatically.
6. If the upgrade takes longer than 10 minutes, the maintenance page shows a warning.

**Volume mounts** in `caddy/docker-compose.yml` that enable this:

```yaml
volumes:
  - ${HOME}/statbus-maintenance:/statbus-maintenance:ro   # Active file
  - ../ops/maintenance:/maintenance-page:ro               # HTML page
  - ../tmp:/statbus-tmp:ro                                # Progress log
```

**Stale cleanup:** On startup, the service checks if a maintenance file exists but no upgrade is actually in progress. If so, it removes the file.

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
| `discovered_at` | `timestamptz` | When the service first saw this release |
| `scheduled_at` | `timestamptz` | When this upgrade was scheduled (set by operator or service) |
| `started_at` | `timestamptz` | When execution began |
| `completed_at` | `timestamptz` | When the upgrade finished successfully |
| `error` | `text` | Error message if the upgrade failed |
| `rolled_back_at` | `timestamptz` | When rollback finished (only if `error` is set) |
| `skipped_at` | `timestamptz` | When the operator chose to skip this version |
| `docker_images_downloaded` | `boolean` | Whether Docker images have been pre-downloaded |
| `backup_path` | `text` | Filesystem path to the pre-upgrade database backup |

**Lifecycle constraint:** The table enforces a CHECK constraint ensuring valid state transitions:
- `completed_at` requires `started_at`
- `started_at` requires `scheduled_at`
- Cannot be both skipped and completed
- `rolled_back_at` requires `error`
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

The upgrade service reads configuration from `.env` (generated from `.env.config`), not from this table. The table provides visibility into the current settings from the admin UI.

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

The service uses the manifest to verify the git checkout SHA (detecting tag spoofing) and to find the correct `sb` binary for self-update.

## Troubleshooting

### Service won't start: "another upgrade service is already running"

The service acquires a PostgreSQL advisory lock (`pg_try_advisory_lock(hashtext('upgrade_daemon'))`). If a previous instance crashed without releasing it, the lock is automatically freed when the database connection closes. Check for stale connections:

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

If the service crashed mid-upgrade, the maintenance file may be stale. The service cleans it automatically on next startup. To clean manually:

```bash
rm ~/statbus-maintenance/active
```

### GitHub rate limiting

Without `GITHUB_TOKEN`, the API allows only 60 requests/hour. The service fetches up to 30 releases per check. Set a token:

```bash
# In systemd override
sudo systemctl edit statbus-upgrade@statbus_no
# Add:
# [Service]
# Environment=GITHUB_TOKEN=ghp_xxxxxxxxxxxxx
```

### Health check fails after upgrade

The service retries the health check 5 times at 5-second intervals. If it still fails, the upgrade is rolled back. Common causes:

- The new version has a startup bug -- check `docker compose logs app`
- Port configuration changed -- verify `.env` has the correct `CADDY_HTTP_PORT`
- Database migrations failed silently -- check `docker compose logs db`

### Pre-download fills disk

Docker images accumulate. The service does not prune old images, only old backup archives (keeps the 3 most recent). Clean up manually:

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

### Database backup/restore

The database data directory is owned by the postgres container user. The upgrade service uses `sudo rsync` for backup and restore. Ensure the service user has passwordless sudo for rsync:

```bash
# /etc/sudoers.d/statbus-backup
statbus_no ALL=(ALL) NOPASSWD: /usr/bin/rsync
```

### Backup archive retention

After each successful upgrade, the pre-upgrade backup is compressed to `~/statbus-backups/<version>-pre.tar.gz`. The service keeps the 3 most recent archives and deletes older ones automatically.
