# STATBUS Cloud Deployment

This directory contains configuration files for running STATBUS in a multi-tenant cloud environment with a shared pgAdmin instance.

## Architecture Overview

```
                                    ┌─────────────────────────────────────┐
                                    │           Host Server               │
                                    │                                     │
    Internet                        │  ┌─────────────────────────────┐   │
        │                           │  │     Host-level Caddy        │   │
        │                           │  │                             │   │
        ├── HTTPS ──────────────────┼─►│  :443 (HTTPS termination)   │   │
        │   ma.statbus.org/*        │  │    ├── /pgadmin ───────────────┼─┬─► pgAdmin (:$PGADMIN_PORT)
        │   no.statbus.org/*        │  │    │   (forward_auth first)│   │ │
        │   al.statbus.org/*        │  │    ├── /rest/* ────────────┼───┼─┼─► tenant REST
        │                           │  │    └── /* ─────────────────┼───┼─┼─► tenant app
        │                           │  │                             │   │ │
        └── PostgreSQL (TLS+SNI) ───┼─►│  :5432 (Layer4 SNI routing) │   │ │
            ma.statbus.org          │  │    ├── @ma ────────────────┼───┼─┼─► ma DB (:3025)
            no.statbus.org          │  │    ├── @no ────────────────┼───┼─┼─► no DB (:3035)
            al.statbus.org          │  │    └── @al ────────────────┼───┼─┼─► al DB (:3045)
                                    │  └─────────────────────────────┘   │ │
                                    │                                     │ │
                                    │  ┌─────────────────────────────┐   │ │
                                    │  │ Shared pgAdmin (:$PGADMIN_PORT)│◄──┼─┘
                                    │  │   (cloud/docker-compose)    │   │
                                    │  └─────────────────────────────┘   │
                                    │                                     │
                                    │  ┌─────────────────────────────┐   │
                                    │  │   Tenant: ma (offset 2)     │   │
                                    │  │   ├── app   :3022           │   │
                                    │  │   ├── rest  :3023           │   │
                                    │  │   ├── db    :3024 (plain)   │   │
                                    │  │   └── db    :3025 (TLS)     │   │
                                    │  └─────────────────────────────┘   │
                                    │                                     │
                                    │  ┌─────────────────────────────┐   │
                                    │  │   Tenant: no (offset 3)     │   │
                                    │  │   ├── app   :3032           │   │
                                    │  │   ├── rest  :3033           │   │
                                    │  │   ├── db    :3034 (plain)   │   │
                                    │  │   └── db    :3035 (TLS)     │   │
                                    │  └─────────────────────────────┘   │
                                    │                                     │
                                    │  ┌─────────────────────────────┐   │
                                    │  │   Tenant: al (offset 4)     │   │
                                    │  │   ...                       │   │
                                    │  └─────────────────────────────┘   │
                                    └─────────────────────────────────────┘
```

## Key Concepts

### Deployment Slots
Each tenant runs in a separate "slot" with isolated ports:
- **Slot offset** determines port numbers: `base = 3000 + (offset × 10)`
- Services per slot: HTTP, HTTPS, app, rest, db (plain), db (TLS)

| Tenant | Offset | App Port | REST Port | DB Plain | DB TLS |
|--------|--------|----------|-----------|----------|--------|
| local  | 1      | 3012     | 3013      | 3014     | 3015   |
| ma     | 2      | 3022     | 3023      | 3024     | 3025   |
| no     | 3      | 3032     | 3033      | 3034     | 3035   |
| al     | 4      | 3042     | 3043      | 3044     | 3045   |

### pgAdmin Authentication Flow
1. User visits `https://ma.statbus.org/pgadmin`
2. Host Caddy's `forward_auth` calls `localhost:3023/rpc/auth_gate` (ma's PostgREST)
3. `auth_gate` checks for valid JWT in cookies:
   - Valid JWT → returns 200 OK → Caddy proxies to pgAdmin
   - No/invalid JWT → returns 401 → Caddy redirects to login page
4. In pgAdmin, user connects to database with their STATBUS credentials
5. pgAdmin connects via external hostname (e.g., `ma.statbus.org:5432`)
6. Host Caddy Layer4 routes by SNI to tenant's TLS port

### Why Shared pgAdmin?
- **Resource efficiency**: One pgAdmin instance serves all tenants
- **Simplified management**: Single place for updates and configuration
- **Tenant isolation maintained**: Each connection goes through proper auth

## Setup Instructions

### 1. Configure Tenant Instances
Each tenant needs its own STATBUS deployment. In each tenant directory:

```bash
# Edit .env.config for each tenant
DEPLOYMENT_SLOT_CODE=ma
DEPLOYMENT_SLOT_PORT_OFFSET=2
CADDY_DEPLOYMENT_MODE=private  # Important: private mode for cloud
ENABLE_PGADMIN=false           # Disable per-instance pgAdmin

# Generate configuration
./devops/manage-statbus.sh generate-config

# Start tenant services
./devops/manage-statbus.sh start all
```

### 2. Configure Shared pgAdmin

```bash
cd cloud

# Create configuration from examples
cp .env.example .env
cp servers.json.example servers.json

# Edit .env - set secure password
nano .env

# Edit servers.json - add your tenant entries
nano servers.json

# Start shared pgAdmin
docker compose -f docker-compose.pgadmin.yml up -d
```

### 3. Configure Host-level Caddy

Install Caddy with Layer4 plugin on the host (not in Docker):

```bash
# Install xcaddy
go install github.com/caddyserver/xcaddy/cmd/xcaddy@latest

# Build Caddy with layer4
xcaddy build --with github.com/mholt/caddy-l4

# Copy example Caddyfile and customize
cp Caddyfile.example /etc/caddy/Caddyfile
nano /etc/caddy/Caddyfile

# Start Caddy
sudo systemctl start caddy
```

### 4. Set Environment Variables for Caddy

Caddy needs to know the pgAdmin port. Either:

```bash
# Option A: Export before starting Caddy
export PGADMIN_PORT=5050
sudo -E systemctl start caddy

# Option B: Add to systemd environment file
echo "PGADMIN_PORT=5050" | sudo tee -a /etc/caddy/environment
sudo systemctl restart caddy
```

### 5. Verify Setup

```bash
# Check pgAdmin is running (use port from .env)
curl -I http://localhost:5050/pgadmin

# Check tenant REST is accessible
curl http://localhost:3023/

# Test full flow (should redirect to login if not authenticated)
curl -I https://ma.statbus.org/pgadmin
```

## Files in This Directory

| File | Purpose |
|------|---------|
| `docker-compose.pgadmin.yml` | Shared pgAdmin Docker Compose |
| `Caddyfile.example` | Full host-level Caddy configuration example |
| `caddy-pgadmin.snippet` | Reusable Caddy snippet for pgAdmin routing |
| `servers.json.example` | pgAdmin server definitions template |
| `.env.example` | Environment variables template |
| `README.md` | This documentation |

## Customization

### Adding a New Tenant

1. **Deploy tenant STATBUS instance** with unique slot offset
2. **Add to servers.json**:
   ```json
   "4": {
     "Name": "New Country STATBUS",
     "Group": "STATBUS Tenants",
     "Host": "xx.statbus.org",
     "Port": 5432,
     "SSLMode": "require",
     "SSLNegotiation": "direct",
     "SSLSNI": true
   }
   ```
3. **Add to host Caddyfile**:
   ```caddyfile
   # Layer4 SNI routing
   @xx tls sni xx.statbus.org
   route @xx {
     proxy localhost:30X5  # tenant's DB-TLS port
   }

   # Site block
   xx.statbus.org {
     import pgadmin_route 30X3  # tenant's REST port
     import tenant_routes 30X2 30X3
     import error_handlers
   }
   ```
4. **Reload services**:
   ```bash
   docker compose -f docker-compose.pgadmin.yml restart
   sudo systemctl reload caddy
   ```

### Removing pgAdmin Access for a Tenant

Simply remove the `import pgadmin_route` line from that tenant's site block in the host Caddyfile.

## Troubleshooting

### pgAdmin shows 401 Unauthorized
- Verify tenant's PostgREST is running: `curl localhost:30X3/`
- Check JWT cookie is set: browser DevTools → Application → Cookies
- Ensure `auth_gate` function exists in tenant database

### Cannot connect to database in pgAdmin
- Verify Layer4 SNI routing: `curl -v --resolve xx.statbus.org:5432:127.0.0.1 postgres://xx.statbus.org:5432/`
- Check tenant's DB-TLS port is exposed
- Ensure SSLSNI patch is applied (custom pgAdmin image)

### pgAdmin not loading static assets
- Verify `SCRIPT_NAME=/pgadmin` is set
- Check Caddy is preserving the path correctly

## Security Considerations

1. **JWT-gated access**: Users must authenticate with STATBUS before accessing pgAdmin
2. **Per-tenant isolation**: Each pgAdmin database connection uses the user's credentials, enforcing RLS
3. **TLS everywhere**: All database connections use TLS via SNI routing
4. **No shared credentials**: pgAdmin master password is only for its internal UI, not database access
