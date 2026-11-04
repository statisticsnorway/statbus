# setup-ubuntu-lts.sh

Ubuntu server setup script — **OS hardening + account creation** —
with interactive stage-by-stage execution. Run once per host; creates the
`devops` ops/admin account and the `statbus` service account that StatBus will
be installed and operated under.

Supported operating systems are Ubuntu 24.04 LTS and Ubuntu 26.04 LTS. The
script reads `/etc/os-release` and refuses unsupported releases before making
changes, in both interactive and non-interactive mode.

This script is the **first of two phases** in a fresh StatBus install:

1. **Setup (this script)** — run as root/sudo, imperative. Hardens the OS and
   creates the Linux users.
2. **Install** — run as the `statbus` service account. Fetches the `sb` binary
   and clones the repository into `~/statbus/`. Covered by
   [install-statbus.md](install-statbus.md) and [DEPLOYMENT.md](DEPLOYMENT.md).

## Quick Start

```bash
# Open a root login shell (HOME=/root, clean environment). Setup run with
# plain sudo from your own home is refused: root must not write root-owned
# files into a non-root home.
sudo -i

# The latest stable release's setup (prompts for configuration, then each stage)
curl -fsSL https://statbus.org/setup.sh | bash

# The newest release candidate's setup
curl -fsSL https://statbus.org/rc/setup.sh | bash

# A specific release (then pass the same --version to install.sh); releases
# before v2026.10.1 do not carry the script as a release asset
curl -fsSL https://github.com/statisticsnorway/statbus/releases/download/v2026.11.0/setup-ubuntu-lts.sh | bash
```

Piped, setup reads its answers from your terminal. Options go after
`bash -s --`, as in the examples below.

## Features

- **Interactive by default** — prompts Yes/No before each stage, safe to run
  from remote/uncomfortable consoles.
- **Verification** — each stage runs checks at the end with green/red
  pass/fail indicators.
- **Configurable** — settings saved to `~/.setup-ubuntu.env`, reused on
  subsequent runs.
- **Non-interactive mode** — `--non-interactive` for automation.
- **Choose stages by name** — `--only-stages` runs just the named stages,
  `--skip-stages` runs all but the named ones (also `ONLY_STAGES` /
  `SKIP_STAGES`). Every stage is safe to rerun.
- **Cloud intent** — `--cloud` (or `CLOUD=true`) declares a cloud
  installation. Only then is the CI question "GitHub repo deploy-key
  sources" (`GITHUB_DEPLOY_KEYS`) asked; a plain standalone preparation
  never asks it. The value can still be set in `~/.setup-ubuntu.env`.

## Stages

Stages have permanent names. They run in this order, and the screen shows the
position only for orientation ("Stage 3 of 9: StatBus service account"). A
stage that acts on something another stage creates requires that stage.

| Name | Requires | What it does |
|------|----------|--------------|
| `https-sources` | | Switch to an HTTPS mirror when the network blocks HTTP (decides by probing) |
| `base-system` | | etckeeper, eternal bash history, locale configuration |
| `service-account` | | `${SERVICE_USER}` (default `statbus`): SSH keys |
| `ssh-hardening` | `service-account` | Confirm remote access, then disable password auth, root password login, empty passwords |
| `auto-updates` | | unattended-upgrades with nightly schedule, email notifications |
| `security-tools` *(optional)* | | CrowdSec IDS + firewall bouncer, UFW firewall |
| `core-tools` | `service-account` | neovim, htop, ripgrep, tmux, Docker CE + compose plugin; Docker access for `${SERVICE_USER}`, then its systemd linger (so the upgrader runs with Docker access) |
| `user-setup` *(cloud-only; needs `--cloud`)* | `core-tools` | `devops` user (ops/admin), GitHub SSH keys, Docker access |
| `ci-allowlist` *(cloud-only; needs `SSHDOERS_REF`)* | | `/etc/sshdoers` from the repo, with a published hash |

The order puts each stage after the ones it requires, so a full run succeeds on
a plain box. The stage table at the top of `ops/setup-ubuntu-lts.sh` is the
single source for names, order, requirements and the configuration each stage
reads.

## Configuration

On first run, you'll be prompted for:

| Variable | Description |
|----------|-------------|
| `ADMIN_EMAIL` | Email for unattended-upgrades notifications |
| `GITHUB_USERS` | Space-separated GitHub usernames for SSH key fetching (populates both `devops` and the service account) |
| `EXTRA_LOCALES` | Extra locales to enable, e.g. `sq_AL nb_NO` (a `.UTF-8` suffix is accepted). Declaring `nb_NO` also adds `no_NO.UTF-8 nb_NO.UTF-8` to `/etc/locale.alias` (unless a `no_NO.UTF-8` alias already exists), so a Mac's forwarded `LC_ALL=no_NO.UTF-8` stops printing a setlocale warning on every SSH login. For other client locales the box lacks, declare that locale here. |
| `SERVICE_USER` | Username for the service account (`service-account` stage; default: `statbus`) |

Configuration is saved to `~/.setup-ubuntu.env` and reused on subsequent runs.

## Non-Interactive Mode

For automation, create the env file first (inside the `sudo -i` root shell, so `~` is `/root`):

```bash
cat > ~/.setup-ubuntu.env << 'EOF'
ADMIN_EMAIL="admin@example.com"
GITHUB_USERS="githubuser1 githubuser2"
EXTRA_LOCALES="sq_AL nb_NO"
SERVICE_USER="statbus"
EOF

curl -fsSL https://statbus.org/setup.sh | bash -s -- --non-interactive
```

### Choosing stages

A full run is the default and is always safe: every stage is idempotent, so
rerunning one on a box where it is already done changes nothing. Choose stages
for what this box should have, not to avoid a stage.

```bash
# Run just some stages, e.g. after a fix in them. A stage's required stages
# must be named too (service-account for ssh-hardening).
curl -fsSL https://statbus.org/setup.sh | bash -s -- --non-interactive --only-stages "service-account ssh-hardening security-tools"

# Leave out a stage this box should not have, e.g. the firewall on a private
# network that has its own.
curl -fsSL https://statbus.org/setup.sh | bash -s -- --non-interactive --skip-stages security-tools

# Environment form
curl -fsSL https://statbus.org/setup.sh | SKIP_STAGES="security-tools" bash -s -- --non-interactive
```

Both options take a space-separated list of names from the Stages table. The
script refuses, before any stage runs and listing the valid names: both options
together, an unknown name, a stage number, or a selection that leaves out a
stage another selected stage requires.

## Post-Setup

After running:

1. **Test SSH as the service account** from a second terminal before closing
   the first:
   ```bash
   ssh "${SERVICE_USER:-statbus}@<host>"
   ```
   This must work before the install phase can proceed.
2. **Test SSH as `devops`** — confirm ops access too. This applies to OUR boxes only: `user-setup` is cloud-only, so a customer standalone prepared without `--cloud` has no `devops` account, and none is expected (STATBUS-501).
3. **Install StatBus** as the service account (see
   [install-statbus.md](install-statbus.md)):
   ```bash
   ssh "${SERVICE_USER:-statbus}@<host>"
   curl -fsSL https://statbus.org/install.sh | bash -s -- --channel prerelease
   ```
4. **Review CrowdSec** (if `security-tools` ran): `cscli metrics`, `cscli decisions list`
5. **Check firewall** (if `security-tools` ran): `ufw status`

## What Gets Set Up

### APT Sources (`https-sources`)
- Probes outbound HTTP and HTTPS first (bounded, 8s max each) and prints the finding
- HTTP reachable: asks nothing and changes nothing
- HTTP blocked: says so and offers to switch to the HTTPS mirror (`mirrors.edge.kernel.org`), default yes

### SSH (`/etc/ssh/sshd_config.d/hardening.conf`)
- Root login: key-only (no password)
- Password authentication: disabled
- Empty passwords: disabled
- Keyboard-interactive auth: disabled

### Firewall (UFW)
- Default: deny incoming, allow outgoing
- Allowed: SSH (22), HTTP (80), HTTPS (443), PostgreSQL (5432)

> **Note**: Skip `security-tools` if your server is on a private network with existing firewall infrastructure.

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
| `devops` | `user-setup` (cloud-only, `--cloud`) | Ops/admin | `devops`, `docker` | yes (passwordless) |
| `${SERVICE_USER}` (default `statbus`) | `service-account`; Docker access from `core-tools` | StatBus deployment | `<user>`, `docker` | no |

The separation is intentional:
- **`devops`** is how you administer the host (journalctl, apt, systemctl,
  etc). Passwordless sudo. Not what StatBus runs under.
- **`${SERVICE_USER}`** owns `~/statbus/` and runs the Docker Compose stack.
  It has `docker` group membership (so `docker ps` and `docker compose` work
  without sudo) and systemd `--user` linger is enabled so
  `statbus-upgrader@<slot>.service` keeps running even when nobody's logged in.
  No sudo.

## Requirements

- Ubuntu 24.04 LTS or Ubuntu 26.04 LTS
- Root/sudo access
- Internet connection (for package downloads + GitHub SSH key fetch)

The script reads `/etc/os-release` `VERSION_ID` and accepts exactly `24.04` or
`26.04`. It refuses every other version before making changes, in both
interactive and non-interactive mode.

## STATBUS Integration

When using this script to prepare a server for STATBUS deployment:

1. **`https-sources`** — Decides itself by probing HTTP egress; it only
   acts (default yes) when HTTP is blocked.
2. **`security-tools`** — Run on public-internet hosts; skip on hosts
   behind an external firewall with its own IDS.
3. **Every other stage** — Essential setup; run them all.

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
