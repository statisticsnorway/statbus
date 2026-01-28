# install-statbus.sh

STATBUS installation script for Ubuntu 24.04 LTS servers.

## Prerequisites

Run the [server hardening script](harden-ubuntu-lts-24.md) first, or ensure you have:
- Docker and Docker Compose installed
- Git installed
- User with docker group access (can run `docker ps` without sudo)

## Quick Start

```bash
# Download and run as your deployment user (e.g., devops)
curl -fsSL https://raw.githubusercontent.com/statisticsnorway/statbus/master/devops/install-statbus.sh -o install-statbus.sh
chmod +x install-statbus.sh
./install-statbus.sh
```

## What It Does

1. **Checks prerequisites** - Verifies Docker, Docker Compose, and Git are installed
2. **Installs Crystal** - Required for the database migrations CLI tool
3. **Clones repository** - Downloads STATBUS to `~/statbus` (or custom directory)
4. **Builds CLI** - Compiles the `statbus` CLI tool for migrations
5. **Creates config files** - Generates initial `.users.yml` and `.env.config`

## Options

| Option | Description |
|--------|-------------|
| `--dir=PATH` | Install to custom directory (default: `~/statbus`) |
| `--help` | Show help message |

## Custom Install Directory

```bash
./install-statbus.sh --dir=/opt/statbus
```

## After Installation

The script will display next steps, but in summary:

1. `cd ~/statbus`
2. Edit `.users.yml` to add admin users
3. Edit `.env.config` to configure deployment settings
4. Run `./devops/manage-statbus.sh generate-config`
5. Run `./devops/manage-statbus.sh start all`
6. Run `./devops/manage-statbus.sh create-db`

See [DEPLOYMENT.md](DEPLOYMENT.md) for detailed configuration options.

## Typical Deployment Flow

```
┌─────────────────────────────────────┐
│  1. Provision Ubuntu 24.04 server   │
└─────────────────┬───────────────────┘
                  │
                  ▼
┌─────────────────────────────────────┐
│  2. Run harden-ubuntu-lts-24.sh     │
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
│  4. Run install-statbus.sh          │
│     (installs Crystal, clones repo) │
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
│     ./devops/manage-statbus.sh ...  │
└─────────────────────────────────────┘
```
