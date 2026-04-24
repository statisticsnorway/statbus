# Installing STATBUS

STATBUS installation for Ubuntu 24.04 LTS servers.

## Prerequisites

Run the [server setup script](setup-ubuntu-lts-24.md) first — it hardens the
OS **and** creates the Linux accounts StatBus expects:

- `devops` — ops/admin user (passwordless sudo, docker group)
- `statbus` — deployment service account that owns the install (docker group,
  no sudo)

If you didn't use that script, ensure you have equivalent state: Docker +
Compose installed, git available, and a non-root Linux user that has docker
group access. That user is what you'll install StatBus under.

## Quick Start

```bash
# From your workstation — SSH as the service account, NOT as devops/ubuntu/root.
# install.sh always installs into $HOME/statbus/ of the invoking user, so
# you get /home/statbus/statbus/ if (and only if) you run it as statbus.
ssh statbus@<your-host>

# Install and configure (clones the repo and runs ./sb install end to end):
curl -fsSL https://statbus.org/install.sh | bash -s -- --channel prerelease
```

If you prefer to do it by hand instead of the bootstrap script:

```bash
ssh statbus@<your-host>
git clone https://github.com/statisticsnorway/statbus.git ~/statbus
cd ~/statbus
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
┌─────────────────────────────────────────┐
│  1. Provision Ubuntu 24.04 server       │
└─────────────────┬───────────────────────┘
                  │
                  ▼
┌─────────────────────────────────────────┐
│  2. Run setup-ubuntu-lts-24.sh          │
│     (as root/sudo)                      │
│     Creates: devops (ops) + statbus     │
│     (service account), hardens OS.      │
└─────────────────┬───────────────────────┘
                  │
                  ▼
┌─────────────────────────────────────────┐
│  3. SSH as the statbus service account  │
│     (NOT devops, NOT ubuntu)            │
└─────────────────┬───────────────────────┘
                  │
                  ▼
┌─────────────────────────────────────────┐
│  4. curl install.sh | bash              │
│     Installs into /home/statbus/statbus │
│     and runs ./sb install end-to-end.   │
└─────────────────┬───────────────────────┘
                  │
                  ▼
┌─────────────────────────────────────────┐
│  5. Configure .env.config + .users.yml  │
│     Re-run ./sb install --non-interactive│
│     (it picks up from where it paused). │
└─────────────────┬───────────────────────┘
                  │
                  ▼
┌─────────────────────────────────────────┐
│  6. Services running, DB migrated.      │
│     Verify: ./sb ps ; ./sb logs proxy   │
└─────────────────────────────────────────┘
```

## Alternative: the `statbus.org/install.sh` bootstrap script

For fresh-server and rescue installs, StatBus also exposes a single-command bootstrap:

```bash
curl -fsSL https://statbus.org/install.sh | bash -s -- --channel prerelease
```

### Where the script source lives

`install.sh` lives at the root of **this** repository:

```
/Users/jhf/ssb/statbus_speed/install.sh
```

(The script was moved here from the sibling `statbus-web` repo at commit
`08bf0420a`, "feat: move install.sh into statbus repo (public)". The
marketing site content stayed in `statbus-web`.)

### Serving chain

```
  statbus.org/install.sh
         │  (302 redirect in /etc/caddy/Caddyfile on niue.statbus.org)
         ▼
  raw.githubusercontent.com/statisticsnorway/statbus/refs/heads/master/install.sh
```

The redirect always points at `master`, so the served script is whatever
is committed to master at the moment the operator runs `curl`.

### Channels

`install.sh` resolves a version via one of three channels, selected by
`--channel <name>` (default: `stable`). Channels are the organizing
principle: there is no moving git tag mediating the resolver. Each
channel has a well-defined, independent resolver path.

| Channel      | Resolver                                              | Binary source           |
|--------------|-------------------------------------------------------|-------------------------|
| `stable`     | GitHub `/releases/latest` (excludes prereleases)      | Release artifact        |
| `prerelease` | Newest `v*-rc.*` via `/releases?per_page=50`          | Release artifact        |
| `edge`       | `master` HEAD; version string becomes `sha-<short>`   | Built from source (`./dev.sh build-sb`, requires `go`) |

Explicit override:

- **`--version vX.Y.Z`** — skip channel resolution and install the
  exact tag. Useful for rollbacks or repeated deterministic installs.

Rationale for the shape:

- **No moving tags.** The `install-verified` tag approach (rc.41-rc.61)
  coupled CI pipeline outcomes to install-time resolver logic, and
  needed `--force` on every consumer's `git fetch` to handle the tag
  being moved. Deleted in rc.62. Channels replace it: each one resolves
  independently from real release metadata, nothing forces tags over.
- **No `--force` anywhere in the installer toolchain.** Silent
  failures previously hid rune's rc.59/rc.60 root causes. Every
  `git fetch --tags` in `install.sh`, `cloud.sh`, and
  `cli/internal/upgrade/github.go` runs without `--force` so operators
  see the real error.
- **Stable is the default** so a bare `curl … | bash` with no flags
  gets the most conservative track.

Migration note (rc.62): `--prerelease` was renamed to
`--channel prerelease`. The old flag now prints an error message
pointing at the new form and exits 1. `cloud.sh` and `standalone.sh`
were updated in the same commit, so operator workflows that shell out
to those scripts continue working without change.

### Updating install.sh

1. Edit `install.sh` in this repo.
2. Commit and push to master.
3. The change is live immediately because the redirect always points
   at `refs/heads/master`. Verify with
   `curl -fsSL https://statbus.org/install.sh | head -5`.

### Concurrency safety

`install.sh` eventually runs `./sb install`, which performs the upgrade-mutex check (see `install-mutex.md`). If an orchestrated upgrade is in flight, the install aborts with a diagnostic message.

To update a live server without tripping the mutex, stop the upgrade service first:

```bash
systemctl --user stop 'statbus-upgrade@*.service'
curl -fsSL https://statbus.org/install.sh | bash -s -- --channel prerelease
```

`./cloud.sh install <server>` does this automatically for both edge and release channels. Fresh installs on a brand-new server have no running service to conflict with.

See `doc/upgrade-system.md` for the full upgrade-system architecture.
