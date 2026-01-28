# StatBus Deployment Guide

This guide is for **system administrators** deploying StatBus for a single country or organization.

**Note**: For multi-tenant cloud deployments (hosting multiple countries), see [CLOUD.md](CLOUD.md).

## Table of Contents

- [Deployment Modes](#deployment-modes)
- [Single Instance Deployment](#single-instance-deployment)
- [Configuration](#configuration)
- [PostgreSQL Access Architecture](#postgresql-access-architecture)
- [Custom TLS Certificates](#custom-tls-certificates)
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
- Supports custom certificates (for organizations with their own CA)
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
curl -fsSL https://raw.githubusercontent.com/statisticsnorway/statbus/master/devops/harden-ubuntu-lts-24.sh -o harden.sh
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

### Quick Install

After hardening, run the STATBUS installer as your deployment user (e.g., `devops`):

```bash
curl -fsSL https://raw.githubusercontent.com/statisticsnorway/statbus/master/devops/install-statbus.sh -o install-statbus.sh
chmod +x install-statbus.sh
./install-statbus.sh
```

This script:
- Verifies prerequisites (Docker, Git)
- Installs Crystal language (for database migrations CLI)
- Clones the STATBUS repository to `~/statbus`
- Builds the CLI tool
- Creates initial configuration files

After installation, follow the on-screen instructions to configure and start STATBUS.

### Manual Installation Steps

If you prefer manual installation, follow these steps:

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

#### 3. Install Crystal and Build CLI

```bash
curl -fsSL https://crystal-lang.org/install.sh | sudo bash
cd cli && shards build --release && cd ..
```

#### 4. Create Users File

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

#### 5. Generate Configuration

```bash
./devops/manage-statbus.sh generate-config
```

This creates:
- `.env` - Main environment file (generated, do not edit directly)
- `.env.credentials` - Secure credentials (generated once, keep secret)
- `.env.config` - Deployment configuration (edit this for your setup)

#### 6. Edit Deployment Configuration

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

**Docker Build** (for HTTPS-only networks):
- `APT_USE_HTTPS_ONLY`: Set to `true` if your network blocks HTTP traffic. This switches Docker image builds to use HTTPS mirrors for apt packages. Default: `false`

> **Note**: The install script (`devops/install-statbus.sh`) automatically detects HTTP-blocked networks and offers to enable this setting.

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

## Custom TLS Certificates

By default, standalone mode uses automatic ACME certificates from Let's Encrypt. If your organization requires using its own certificates (e.g., from an internal CA or a specific certificate provider), you can configure StatBus to use custom certificates instead.

### Certificate Requirements

Your certificate files must be:
- **PEM format** (base64 encoded)
- **Fullchain format** for the certificate file (server certificate + intermediate CA certificates concatenated)
- **Unencrypted** private key (no password protection)

### Directory Structure

Caddy's data directory is mounted at `caddy/data/`:

```
caddy/data/
├── caddy/              # Caddy-managed (ACME certs, internal PKI)
│   ├── certificates/   # Auto-obtained certificates
│   └── pki/            # Internal CA for development mode
└── custom-certs/       # Your custom certificates go here
```

The `caddy/data/` directory is gitignored to protect sensitive private keys.

### Setup Instructions

#### 1. Prepare Certificate Files

**Option A: Converting from PFX/PKCS#12 format (most common)**

Many certificate providers deliver certificates as `.pfx` or `.p12` files (password-protected). Use the included conversion script:

```bash
./devops/convert-pfx-cert.sh /path/to/certificate.pfx domain-name
```

The script will:
- Prompt for the PFX password
- Extract the certificate chain and private key
- Place files in `caddy/data/custom-certs/`
- Set secure permissions
- **Automatically update `.env.config`** with the certificate paths
- **Automatically regenerate** the Caddy configuration
- **Offer to restart Caddy** to apply the new certificate

Example:
```bash
./devops/convert-pfx-cert.sh ~/Downloads/statbus-albania.pfx albania
# Enter password when prompted
# Script handles everything - just confirm the Caddy restart
```

That's it! The script handles the entire process end-to-end.

**Option B: From separate PEM files**

If you received separate certificate and CA chain files, concatenate them into fullchain format:

```bash
# Concatenate server cert + intermediate CA(s) + root CA (if provided)
cat server.crt intermediate.crt > caddy/data/custom-certs/domain.crt

# Or if you have a separate CA bundle file:
cat server.crt ca-bundle.crt > caddy/data/custom-certs/domain.crt

# Copy the private key
cp server.key caddy/data/custom-certs/domain.key

# Set secure permissions
chmod 600 caddy/data/custom-certs/domain.key
```

The fullchain order should be:
1. Server certificate (your domain)
2. Intermediate CA certificate(s)
3. Root CA certificate (optional, usually not needed)

#### 2. Configure Environment

Edit `.env.config` and set the certificate paths:

```bash
# Custom TLS certificate paths (inside container)
TLS_CERT_FILE=/data/custom-certs/domain.crt
TLS_KEY_FILE=/data/custom-certs/domain.key
```

#### 3. Regenerate Configuration

```bash
./devops/manage-statbus.sh generate-config
```

This updates the Caddy configuration to use your custom certificates instead of ACME.

#### 4. Restart Caddy

```bash
docker compose restart proxy
```

#### 5. Verify Certificate

```bash
# Check certificate details
openssl s_client -connect your-domain.com:443 -servername your-domain.com < /dev/null 2>/dev/null | openssl x509 -noout -text | head -20

# Or use curl
curl -vI https://your-domain.com 2>&1 | grep -A5 "Server certificate"
```

### Switching Back to ACME

To return to automatic Let's Encrypt certificates:

1. Clear the certificate paths in `.env.config`:
   ```bash
   TLS_CERT_FILE=
   TLS_KEY_FILE=
   ```

2. Regenerate and restart:
   ```bash
   ./devops/manage-statbus.sh generate-config
   docker compose restart proxy
   ```

### Certificate Renewal

**Custom certificates**: You are responsible for renewing and replacing certificate files before expiry. After updating files in `caddy/data/custom-certs/`, restart Caddy:
```bash
docker compose restart proxy
```

**ACME certificates**: Caddy handles renewal automatically (no action needed).

### Inspecting Certificates

You can inspect both ACME-managed and custom certificates directly on the host:

```bash
# View ACME certificates (if using Let's Encrypt)
ls -la caddy/data/caddy/certificates/

# View custom certificates
ls -la caddy/data/custom-certs/

# Check certificate expiry
openssl x509 -in caddy/data/custom-certs/domain.crt -noout -enddate
```

### Troubleshooting Custom Certificates

**Certificate not loading**:
```bash
# Check Caddy logs for TLS errors
docker compose logs proxy | grep -i tls

# Verify certificate chain is valid
openssl verify -CAfile ca-bundle.crt caddy/data/custom-certs/domain.crt
```

**"certificate signed by unknown authority"**:
- Ensure the fullchain includes all intermediate certificates
- Verify the certificate order (server cert first, then intermediates)

**Permission denied**:
```bash
# Ensure files are readable by the container
chmod 644 caddy/data/custom-certs/domain.crt
chmod 600 caddy/data/custom-certs/domain.key
```

---
