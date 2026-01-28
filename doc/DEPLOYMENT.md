# StatBus Deployment Guide

This guide is for **system administrators** deploying StatBus for a single country or organization.

**Note**: For multi-tenant cloud deployments (hosting multiple countries), see [CLOUD.md](CLOUD.md).

## Table of Contents

- [Deployment Modes](#deployment-modes)
- [Single Instance Deployment](#single-instance-deployment)
- [Configuration](#configuration)
- [PostgreSQL Access Architecture](#postgresql-access-architecture)
- [Troubleshooting](#troubleshooting)
- [Security Considerations](#security-considerations)

---

## Deployment Modes

StatBus supports three deployment modes, controlled by the `CADDY_DEPLOYMENT_MODE` environment variable:

### 1. Development Mode

**Purpose**: Local development with hot-reload

**Characteristics**:
- HTTP only (no HTTPS)
- Self-signed internal CA certificates
- PostgreSQL accessible on custom port (default: 3024)
- Domain: `local.statbus.org` (resolves to 127.0.0.1)
- Next.js runs separately on host machine (`pnpm run dev`)

**Use case**: Developers working on StatBus source code

### 2. Standalone Mode

**Purpose**: Single-server production deployment

**Characteristics**:
- Handles HTTPS directly with automatic ACME/Let's Encrypt certificates
- PostgreSQL accessible on standard port 5432 with TLS+SNI
- All services run in Docker
- Direct public access without additional proxy

**Use case**: National statistical office deploying for one country

**Requirements**:
- Public domain name (e.g., `statbus.example.com`)
- DNS A record pointing to server IP
- Open ports: 80 (HTTP), 443 (HTTPS), 5432 (PostgreSQL)

### 3. Private Mode

**Purpose**: Behind host-level reverse proxy

**Characteristics**:
- HTTP only (HTTPS handled by host proxy)
- Trusts X-Forwarded-* headers from proxy
- PostgreSQL forwarding from host proxy to Docker network
- Multiple instances can run on same host (different ports)

**Use case**: Part of multi-tenant cloud deployment

---

## Single Instance Deployment

This section covers deploying StatBus for a single country or organization.

### Prerequisites

**Server Requirements**:
- **OS**: Linux (Ubuntu 24.04 LTS recommended)
- **CPU**: 4 cores minimum
- **RAM**: 16 GB minimum
- **Disk**: 100 GB minimum (depends on data volume)
- **Network**: Public IP address with open ports 80, 443, 5432

**Software Requirements**:
- Docker 24.0+
- Docker Compose 2.20+
- Git
- Crystal (for CLI migrations tool)

#### Installing Prerequisites on Ubuntu

**Install Git**:
```bash
sudo apt update
sudo apt install -y git
```

**Install Docker and Docker Compose**:

Add Docker's official GPG key:
```bash
sudo apt install -y ca-certificates curl gnupg
sudo install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
sudo chmod a+r /etc/apt/keyrings/docker.gpg
```

Add Docker repository:
```bash
echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
  $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | \
  sudo tee /etc/apt/sources.list.d/docker.list
```

Install Docker:
```bash
sudo apt update
sudo apt install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
```

Add your user to docker group (to run docker without sudo):
```bash
sudo usermod -aG docker $USER
newgrp docker
```

**Important Docker Security Note**:
Docker Compose bypasses UFW firewall rules. Ensure you carefully review which ports are exposed in docker-compose.yml files. StatBus minimizes exposure by binding sensitive ports to localhost only in private mode.

**Install Crystal** (for database migrations CLI):
```bash
curl -fsSL https://crystal-lang.org/install.sh | sudo bash
```

Verify installation:
```bash
crystal --version
shards --version
```

### Server Hardening (Recommended)

Before installing StatBus on a production server, we recommend hardening the Ubuntu installation:

```bash
curl -fsSL https://raw.githubusercontent.com/statisticsnorway/statbus/main/doc/harden-ubuntu-lts-24.sh -o harden.sh
chmod +x harden.sh
sudo ./harden.sh
```

This interactive script configures:
- HTTPS APT sources (optional, for networks that block HTTP)
- SSH key-only authentication (no passwords)
- Automatic security updates
- CrowdSec intrusion detection and UFW firewall (optional for private networks)
- Docker and essential tools
- `devops` user with GitHub SSH keys

**For STATBUS deployments:**
- **Run Stage 0** if your network blocks HTTP (switches APT to HTTPS mirror)
- **Skip Stage 4** if your server is on a private network with existing firewall infrastructure
- **Skip Stage 7** (Caddy) — StatBus runs Caddy inside Docker

See [Server Hardening Guide](harden-ubuntu-lts-24.md) for full details.

### Installation Steps

#### 1. Clone Repository

```bash
# On your server
git clone https://github.com/statisticsnorway/statbus.git
cd statbus
```

#### 2. Configure Git Hooks

```bash
git config core.hooksPath devops/githooks
```

#### 3. Create Users File

```bash
cp .users.example .users.yml
nano .users.yml  # Edit to add your admin users
```

Example `.users.yml`:
```yaml
users:
  - email: admin@example.com
    password: your-secure-password
    role: admin_user
  - email: analyst@example.com
    password: another-secure-password
    role: regular_user
```

#### 4. Generate Configuration

```bash
./devops/manage-statbus.sh generate-config
```

This creates:
- `.env` - Main environment file (generated, do not edit directly)
- `.env.credentials` - Secure credentials (generated once, keep secret)
- `.env.config` - Deployment configuration (edit this for your setup)

#### 5. Edit Deployment Configuration

```bash
nano .env.config
```

**Key settings for standalone deployment**:

```bash
# Deployment identification
DEPLOYMENT_SLOT_NAME="Your Country StatBus"
DEPLOYMENT_SLOT_CODE="your_country"  # Short code (lowercase, no spaces)

# Deployment mode
CADDY_DEPLOYMENT_MODE=standalone

# Your public domain
SITE_DOMAIN=statbus.example.com

# Port configuration (default values work for standalone)
CADDY_HTTP_BIND_ADDRESS=0.0.0.0
CADDY_HTTPS_BIND_ADDRESS=0.0.0.0
CADDY_DB_BIND_ADDRESS=0.0.0.0
CADDY_DB_PORT=5432  # Standard PostgreSQL port
```

After editing, regenerate:
```bash
./devops/manage-statbus.sh generate-config
```

#### 6. Start Services

```bash
# Start all Docker containers
./devops/manage-statbus.sh start all

# Initialize database (first time only)
./devops/manage-statbus.sh create-db-structure
./devops/manage-statbus.sh create-users

# Apply migrations
./cli/bin/statbus migrate up
```

#### 7. Verify Deployment

```bash
# Check all services are running
docker compose ps

# Check Caddy logs
docker compose logs --tail=50 proxy

# Check database connectivity
./devops/manage-statbus.sh psql -c "SELECT version();"
```

#### 8. Access Your Instance

- **Web Interface**: https://statbus.example.com
- **API**: https://statbus.example.com/rest/
- **PostgreSQL**: statbus.example.com:5432 (with TLS)

### Ongoing Management

**Start/Stop Services**:
```bash
./devops/manage-statbus.sh stop
./devops/manage-statbus.sh start all
```

**View Logs**:
```bash
docker compose logs -f proxy   # Caddy logs
docker compose logs -f db      # PostgreSQL logs
docker compose logs -f app     # Next.js logs
docker compose logs -f rest    # PostgREST logs
```

**Database Backup**:
```bash
# Backup
docker compose exec db pg_dump -U postgres statbus > backup_$(date +%Y%m%d).sql

# Restore
cat backup_20240115.sql | docker compose exec -T db psql -U postgres statbus
```

**Apply Migrations**:
```bash
./cli/bin/statbus migrate up
```

**Update StatBus**:
```bash
git pull
./devops/manage-statbus.sh stop
docker compose build
./cli/bin/statbus migrate up
./devops/manage-statbus.sh start all
```

---

## Configuration

### Environment Variables

StatBus uses a layered configuration approach:

```
.env.credentials (generated once, contains secrets)
       +
.env.config (edit this for deployment settings)
       ↓
   generate-config
       ↓
     .env (generated, used by Docker Compose)
```

**Key Configuration Files**:

| File | Purpose | Edit? |
|------|---------|-------|
| `.env.config` | Deployment settings | ✅ Yes |
| `.env.credentials` | Secure credentials | ❌ No (generated once) |
| `.env` | Generated environment | ❌ No (regenerated) |
| `.users.yml` | Initial user accounts | ✅ Yes |

### Important Environment Variables

**Deployment Identity**:
- `DEPLOYMENT_SLOT_NAME`: Human-readable name
- `DEPLOYMENT_SLOT_CODE`: Short code for URLs and container names

**Network Configuration**:
- `CADDY_HTTP_BIND_ADDRESS`: IP for HTTP (default: `0.0.0.0`)
- `CADDY_HTTPS_BIND_ADDRESS`: IP for HTTPS (default: `0.0.0.0`)
- `CADDY_DB_BIND_ADDRESS`: IP for PostgreSQL (default: `0.0.0.0`)
- `CADDY_DB_PORT`: PostgreSQL port (default: 5432 for standalone, 3024 for development)

**Deployment Mode**:
- `CADDY_DEPLOYMENT_MODE`: `development` | `standalone` | `private`

**Domain**:
- `SITE_DOMAIN`: Your public domain (required for standalone and private modes)

### Docker Compose Profiles

Control which services start:

```bash
# All services (default)
./devops/manage-statbus.sh start all

# Backend only (no Next.js app)
./devops/manage-statbus.sh start all_except_app
```

---

## PostgreSQL Access Architecture

### Standalone Mode Architecture

```
Client (psql, app)
    ↓ TLS connection to statbus.example.com:5432
    ↓ with SNI = statbus.example.com
    ↓ and ALPN = postgresql
    ↓
Caddy (Layer4 TLS proxy)
    ↓ Terminates TLS using ACME certificate
    ↓ Matches SNI + ALPN
    ↓ Forwards plain TCP to db:5432 (Docker network)
    ↓
PostgreSQL container
    ✓ Receives plain TCP connection
```

**Benefits**:
- TLS encryption for all PostgreSQL connections
- PostgreSQL doesn't need TLS configuration
- Standard port 5432
- Automatic certificate management via Let's Encrypt

### Connection Details

Users connect with:
```bash
export PGHOST=statbus.example.com
export PGPORT=5432
export PGDATABASE=statbus
export PGUSER=username
export PGPASSWORD=password
export PGSSLNEGOTIATION=direct
export PGSSLMODE=verify-full
export PGSSLSNI=1
psql
```

See [Integration Guide](../integration/README.md#postgresql-direct-access) for detailed connection examples.

---
