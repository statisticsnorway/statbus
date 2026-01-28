# harden-ubuntu-lts-24.sh

Ubuntu 24.04 LTS server hardening script with interactive stage-by-stage execution.

## Quick Start

```bash
# Download
curl -fsSL https://raw.githubusercontent.com/statisticsnorway/statbus/main/devops/harden-ubuntu-lts-24.sh -o harden.sh
chmod +x harden.sh

# Run (will prompt for configuration, then each stage)
sudo ./harden.sh
```

## Features

- **Interactive**: Prompts Yes/No before each stage - safe to run from uncomfortable consoles
- **Verification**: Automatic checks after each stage with pass/fail indicators
- **Configurable**: Settings stored in `~/.harden-ubuntu.env`
- **Non-interactive mode**: `--non-interactive` flag for automation

## Stages

| # | Stage | What it does |
|---|-------|--------------|
| 0 | HTTPS APT Sources *(optional)* | Switch to HTTPS mirror for networks that block HTTP |
| 1 | Base System | etckeeper, eternal bash history, locale configuration |
| 2 | SSH Hardening | Disable password auth, root password login, empty passwords |
| 3 | Auto Updates | unattended-upgrades with nightly schedule, email notifications |
| 4 | Security Tools *(optional)* | CrowdSec IDS + firewall bouncer, UFW firewall |
| 5 | Core Tools | neovim, htop, ripgrep, Docker CE + compose |
| 6 | User Setup | devops user, GitHub SSH keys, Homebrew, helix/bottom/zellij |
| 7 | Caddy *(optional)* | Caddy web server with optional plugin support via xcaddy |

## Configuration

On first run, you'll be prompted for:

| Variable | Description |
|----------|-------------|
| `ADMIN_EMAIL` | Email for unattended-upgrades notifications |
| `GITHUB_USERS` | Space-separated GitHub usernames for SSH key fetching |
| `EXTRA_LOCALES` | Extra locales to enable, without `.UTF-8` suffix (e.g., `sq_AL nb_NO`) |
| `CADDY_PLUGINS` | Caddy plugins for custom build (empty = standard Caddy) |

Configuration is saved to `~/.harden-ubuntu.env` and reused on subsequent runs.

### Caddy Plugin Options

When prompted, select by number or enter custom plugin paths:

1. `github.com/mholt/caddy-l4` - Layer 4 (TCP/UDP) proxying
2. `github.com/caddy-dns/cloudflare` - Cloudflare DNS for ACME
3. `github.com/caddy-dns/namedotcom` - Name.com DNS for ACME
4. `github.com/caddy-dns/route53` - AWS Route53 DNS for ACME
5. `github.com/caddy-dns/digitalocean` - DigitalOcean DNS for ACME
6. `github.com/greenpau/caddy-security` - Authentication/Authorization

## Non-Interactive Mode

For automation, create the `.env` file first:

```bash
cat > ~/.harden-ubuntu.env << 'EOF'
ADMIN_EMAIL="admin@example.com"
GITHUB_USERS="githubuser1 githubuser2"
EXTRA_LOCALES="sq_AL nb_NO"
CADDY_PLUGINS=""
EOF

sudo ./harden.sh --non-interactive
```

## Post-Installation

After running:

1. **Test SSH access** as `devops` user before closing console session
2. **Configure Caddy** at `/etc/caddy/Caddyfile`
3. **Review CrowdSec**: `cscli metrics`, `cscli decisions list`
4. **Check firewall**: `ufw status`

## What Gets Hardened

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

## Requirements

- Ubuntu 24.04 LTS
- Root/sudo access
- Internet connection (for package downloads)

## STATBUS Integration

When using this script to prepare a server for STATBUS deployment:

1. **Stage 0 (HTTPS Sources)** — Run if your network blocks HTTP traffic
2. **Run Stages 1-3, 5-6** — Essential hardening and tools
3. **Stage 4 (Security Tools)** — Skip if on a private network with existing firewall
4. **Stage 7 (Caddy)** — Skip, as STATBUS runs Caddy inside Docker

After hardening, log in as the `devops` user and run the STATBUS installer:

```bash
curl -fsSL https://raw.githubusercontent.com/statisticsnorway/statbus/main/devops/install-statbus.sh -o install-statbus.sh
chmod +x install-statbus.sh
./install-statbus.sh
```

See [install-statbus.md](install-statbus.md) and [DEPLOYMENT.md](DEPLOYMENT.md) for details.

## License

MIT
