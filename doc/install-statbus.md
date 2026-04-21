# Installing STATBUS

STATBUS installation for Ubuntu 24.04 LTS servers.

## Prerequisites

Run the [server hardening script](setup-ubuntu-lts-24.md) first, or ensure you have:
- Docker and Docker Compose installed
- Git installed
- User with docker group access (can run `docker ps` without sudo)

## Quick Start

```bash
# Clone the repository
git clone https://github.com/statisticsnorway/statbus.git ~/statbus
cd ~/statbus

# Install and configure
./sb install
```

## What It Does

`./sb install` is the unified entrypoint for first-install, repair, and dispatching a pending upgrade. It probes the install directory (the 8-state ladder in `cli/internal/install/state.go`) and routes to the right action:

- **Fresh directory** — runs the step-table: checks prerequisites (Docker, Docker Compose, Git), clones the repository, writes initial `.users.yml` and `.env.config`, generates credentials, and starts services.
- **Existing install with no pending upgrade** — runs the same step-table as an idempotent config-refresh checkpoint. Safe to re-run.
- **Scheduled upgrade pending** (a row in `public.upgrade` with state=`scheduled`) — dispatches the upgrade inline through the same pipeline the service uses (backup, checkout, migrate, restart, health-check, rollback on failure).
- **Stale crashed-upgrade flag** — reconciles the flag, re-probes state, and re-dispatches.
- **Live upgrade running** — refuses and points at `journalctl --user -u 'statbus-upgrade@*' -f`.
- **Pre-1.0 database** (no `public.upgrade` table) — refuses and points at the manual upgrade path in `doc/CLOUD.md`.

For operator-triggered upgrades on an existing install, the canonical workflow is: `./sb upgrade schedule <version>` to queue, then either wait for the systemd service's next tick, or run `./sb install` to dispatch immediately.

See `doc/upgrade-system.md` for the full dispatch reference and `doc/install-mutex.md` for the concurrency contract.

## After Installation

The installer will display next steps, but in summary:

1. `cd ~/statbus`
2. Edit `.users.yml` to add admin users
3. Edit `.env.config` to configure deployment settings
4. Run `./sb config generate`
5. Run `./sb start all`
6. Run `./dev.sh create-db`

See [DEPLOYMENT.md](DEPLOYMENT.md) for detailed configuration options.

## Typical Deployment Flow

```
┌─────────────────────────────────────┐
│  1. Provision Ubuntu 24.04 server   │
└─────────────────┬───────────────────┘
                  │
                  ▼
┌─────────────────────────────────────┐
│  2. Run setup-ubuntu-lts-24.sh     │
│     (as root, creates devops user)  │
└─────────────────┬───────────────────┘
                  │
                  ▼
┌─────────────────────────────────────┐
│  3. SSH as devops user              │
└─────────────────┬───────────────────┘
                  │
                  ▼
┌─────────────────────────────────────┐
│  4. Clone repo and run ./sb install │
└─────────────────┬───────────────────┘
                  │
                  ▼
┌─────────────────────────────────────┐
│  5. Configure .env.config           │
│     and .users.yml                  │
└─────────────────┬───────────────────┘
                  │
                  ▼
┌─────────────────────────────────────┐
│  6. Start services and create DB    │
│     ./sb start all && ./dev.sh ...  │
└─────────────────────────────────────┘
```

## Alternative: the `statbus.org/install.sh` bootstrap script

For fresh-server and rescue installs, StatBus also exposes a single-command bootstrap:

```bash
curl -fsSL https://statbus.org/install.sh | bash -s -- --prerelease
```

### Where the script source lives

**Not in this repository.** It lives in the sibling repo:

```
/Users/jhf/ssb/statbus-web/install.sh
```

That same repo also owns the marketing site content.

### Serving chain

```
  statbus.org/install.sh
         │  (301 redirect in /etc/caddy/Caddyfile on niue.statbus.org)
         ▼
  www.statbus.org/install.sh
         │  (Caddy file_server, root = /home/statbus_www/public_html)
         ▼
  /home/statbus_www/public_html/install.sh on niue.statbus.org
```

The file on the server is synced from the statbus-web repo by CI.

### Deployment pipeline

Push to `master` in `statbus-web` → `.github/workflows/deploy.yml` SSHes as `statbus_www@niue.statbus.org` → server-side `deploy.sh` syncs files into `/home/statbus_www/public_html/`.

No manual server-side editing is needed; changes go through normal git + CI.

### Updating install.sh

1. Edit `/Users/jhf/ssb/statbus-web/install.sh`.
2. Commit and push to master in statbus-web.
3. Verify: `curl -fsSL https://statbus.org/install.sh | head -5` should show the change after CI runs.

### Concurrency safety

`install.sh` eventually runs `./sb install`, which performs the upgrade-mutex check (see `install-mutex.md`). If an orchestrated upgrade is in flight, the install aborts with a diagnostic message.

To update a live server without tripping the mutex, stop the upgrade service first:

```bash
systemctl --user stop 'statbus-upgrade@*.service'
curl -fsSL https://statbus.org/install.sh | bash -s -- --prerelease
```

`./cloud.sh install <server>` does this automatically for both edge and release channels. Fresh installs on a brand-new server have no running service to conflict with.

See `doc/upgrade-system.md` for the full upgrade-system architecture.
