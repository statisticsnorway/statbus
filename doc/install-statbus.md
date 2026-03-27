# Installing STATBUS

STATBUS installation for Ubuntu 24.04 LTS servers.

## Prerequisites

Run the [server hardening script](harden-ubuntu-lts-24.md) first, or ensure you have:
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

1. **Checks prerequisites** - Verifies Docker, Docker Compose, and Git are installed
2. **Clones repository** - Downloads STATBUS to `~/statbus` (or custom directory)
3. **Creates config files** - Generates initial `.users.yml` and `.env.config`

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
