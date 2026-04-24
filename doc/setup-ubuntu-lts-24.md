# setup-ubuntu-lts-24.sh

Ubuntu 24.04 LTS server setup script — **OS hardening + account creation** —
with interactive stage-by-stage execution. Run once per host; creates the
`devops` ops/admin account and the `statbus` service account that StatBus will
be installed and operated under.

This script is the **first of two phases** in a fresh StatBus install:

1. **Setup (this script)** — run as root/sudo, imperative. Hardens the OS and
   creates the Linux users.
2. **Install** — run as the `statbus` service account. Fetches the `sb` binary
   and clones the repository into `~/statbus/`. Covered by
   [install-statbus.md](install-statbus.md) and [DEPLOYMENT.md](DEPLOYMENT.md).

## Quick Start

```bash
# Download
curl -fsSL https://raw.githubusercontent.com/statisticsnorway/statbus/master/ops/setup-ubuntu-lts-24.sh -o setup.sh
chmod +x setup.sh

# Run (will prompt for configuration, then each stage)
sudo ./setup.sh
```

## Features

- **Interactive by default** — prompts Yes/No before each stage, safe to run
  from remote/uncomfortable consoles.
- **Verification** — each stage runs checks at the end with green/red
  pass/fail indicators.
- **Configurable** — settings saved to `~/.setup-ubuntu.env`, reused on
  subsequent runs.
- **Non-interactive mode** — `--non-interactive` for automation.
- **Per-stage skip** — `SKIP_STAGES` env var or `--skip-stages` flag to
  short-circuit specific stages in either mode.

## Stages

| # | Stage | What it does |
|---|-------|--------------|
| 0 | HTTPS APT Sources *(optional)* | Switch to HTTPS mirror for networks that block HTTP |
| 1 | Base System | etckeeper, eternal bash history, locale configuration |
| 2 | SSH Hardening | Disable password auth, root password login, empty passwords |
| 3 | Auto Updates | unattended-upgrades with nightly schedule, email notifications |
| 4 | Security Tools *(optional)* | CrowdSec IDS + firewall bouncer, UFW firewall |
| 5 | Core Tools | neovim, htop, ripgrep, Docker CE + compose plugin |
| 6 | User Setup | `devops` user (ops/admin), GitHub SSH keys, Homebrew, helix/bottom/zellij |
| 7 | StatBus Service Account | `${SERVICE_USER}` (default `statbus`): docker group, SSH keys, systemd linger |

## Configuration

On first run, you'll be prompted for:

| Variable | Description |
|----------|-------------|
| `ADMIN_EMAIL` | Email for unattended-upgrades notifications |
| `GITHUB_USERS` | Space-separated GitHub usernames for SSH key fetching (populates both `devops` and the service account) |
| `EXTRA_LOCALES` | Extra locales to enable, without `.UTF-8` suffix (e.g., `sq_AL nb_NO`) |
| `SERVICE_USER` | Username for the Stage 7 service account (default: `statbus`) |

Configuration is saved to `~/.setup-ubuntu.env` and reused on subsequent runs.

## Non-Interactive Mode

For automation, create the env file first:

```bash
cat > ~/.setup-ubuntu.env << 'EOF'
ADMIN_EMAIL="admin@example.com"
GITHUB_USERS="githubuser1 githubuser2"
EXTRA_LOCALES="sq_AL nb_NO"
SERVICE_USER="statbus"
EOF

sudo ./setup.sh --non-interactive
```

### Skipping specific stages

Both interactive and non-interactive runs honor `SKIP_STAGES` and
`--skip-stages`:

```bash
# Skip stage 0 (keep HTTP APT sources) — typical for Hetzner dedicated hosts
SKIP_STAGES="0" sudo ./setup.sh --non-interactive

# Equivalent CLI form
sudo ./setup.sh --non-interactive --skip-stages "0"

# Skip multiple
SKIP_STAGES="0 4" sudo ./setup.sh --non-interactive
```

Stages to skip are a space-separated list of the numbers from the Stages table.

## Post-Setup

After running:

1. **Test SSH as the service account** from a second terminal before closing
   the first:
   ```bash
   ssh "${SERVICE_USER:-statbus}@<host>"
   ```
   This must work before the install phase can proceed.
2. **Test SSH as `devops`** — confirm ops access too.
3. **Install StatBus** as the service account (see
   [install-statbus.md](install-statbus.md)):
   ```bash
   ssh "${SERVICE_USER:-statbus}@<host>"
   curl -fsSL https://statbus.org/install.sh | bash -s -- --channel prerelease
   ```
4. **Review CrowdSec** (if Stage 4 ran): `cscli metrics`, `cscli decisions list`
5. **Check firewall** (if Stage 4 ran): `ufw status`

## What Gets Set Up

### APT Sources (Stage 0)
- Switches from HTTP to HTTPS mirror (`mirrors.edge.kernel.org`)
- Required for networks that block unencrypted HTTP traffic

> **Note**: Skip Stage 0 if your network allows HTTP or you prefer a different mirror.

### SSH (`/etc/ssh/sshd_config.d/hardening.conf`)
- Root login: key-only (no password)
- Password authentication: disabled
- Empty passwords: disabled
- Keyboard-interactive auth: disabled

### Firewall (UFW)
- Default: deny incoming, allow outgoing
- Allowed: SSH (22), HTTP (80), HTTPS (443), PostgreSQL (5432)

> **Note**: Skip Stage 4 if your server is on a private network with existing firewall infrastructure.

### Intrusion Detection (CrowdSec)
- SSH brute-force protection
- Caddy log analysis (prepared)
- nftables firewall bouncer for automatic IP banning

### Memory Tuning (`/etc/sysctl.d/20-server-tuning.conf`)
- `vm.swappiness=1` - Minimize swapping for server workloads
- Dirty page limits tuned for predictable I/O

### Accounts Created

| User | Created by | Role | Groups | sudo |
|------|-----------|------|--------|------|
| `devops` | Stage 6 | Ops/admin | `devops`, `docker` | yes (passwordless) |
| `${SERVICE_USER}` (default `statbus`) | Stage 7 | StatBus deployment | `<user>`, `docker` | no |

The separation is intentional:
- **`devops`** is how you administer the host (journalctl, apt, systemctl,
  etc). Passwordless sudo. Not what StatBus runs under.
- **`${SERVICE_USER}`** owns `~/statbus/` and runs the Docker Compose stack.
  It has `docker` group membership (so `docker ps` and `docker compose` work
  without sudo) and systemd `--user` linger is enabled so
  `statbus-upgrade@<slot>.service` keeps running even when nobody's logged in.
  No sudo.

## Requirements

- Ubuntu 24.04 LTS
- Root/sudo access
- Internet connection (for package downloads + GitHub SSH key fetch)

## STATBUS Integration

When using this script to prepare a server for STATBUS deployment:

1. **Stage 0 (HTTPS Sources)** — Run if your network blocks HTTP traffic (skip
   otherwise, e.g. `SKIP_STAGES="0"` on Hetzner dedicated).
2. **Stages 1-3, 5-7** — Essential setup, run all of them.
3. **Stage 4 (Security Tools)** — Run on public-internet hosts; skip on hosts
   behind an external firewall with its own IDS.

After setup finishes, continue with the install phase as the service account:

```bash
ssh "${SERVICE_USER:-statbus}@<host>"
curl -fsSL https://statbus.org/install.sh | bash -s -- --channel prerelease
```

See [install-statbus.md](install-statbus.md) and [DEPLOYMENT.md](DEPLOYMENT.md)
for the rest of the install flow. For **Hetzner-specific bootstrap** (rescue →
Ubuntu install → handoff to this script), see
[hetzner-bootstrap.md](hetzner-bootstrap.md).

## License

MIT
