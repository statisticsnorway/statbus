# StatBus Development Guide

This guide is for **developers** contributing to the StatBus codebase.

For deploying StatBus, see [Deployment Guide](DEPLOYMENT.md).  
For using StatBus, see [User Guide](USAGE.md).

## Table of Contents

- [Development Setup](#development-setup)
- [Project Structure](#project-structure)
- [Local Development Workflow](#local-development-workflow)
- [Database Development](#database-development)
- [Frontend Development](#frontend-development)
- [Code Conventions](#code-conventions)
- [Testing](#testing)
- [Architecture](#architecture)

---

## Development Setup

### Prerequisites

**Required Tools**:
- **Docker** 24.0+ and **Docker Compose** 2.20+
- **Git** 2.40+
- **Node.js** (version specified in `.nvmrc`)
- **pnpm** 8.0+

**Platform-Specific**:

**macOS**:
```bash
# Install Homebrew
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

# Install tools
brew install nvm git docker docker-compose crystal-lang
brew install --cask docker  # Docker Desktop
```

**Linux (Ubuntu/Debian)**:
```bash
# Install Docker
curl -fsSL https://get.docker.com -o get-docker.sh
sudo sh get-docker.sh

# Install Crystal (for database migrations)
curl -fsSL https://crystal-lang.org/install.sh | sudo bash

# Verify Crystal installation
crystal --version
shards --version

# Install Node Version Manager
curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.0/install.sh | bash

# Install pnpm
curl -fsSL https://get.pnpm.io/install.sh | sh -
```

**Windows**:
```bash
# Install Scoop
Set-ExecutionPolicy RemoteSigned -Scope CurrentUser
irm get.scoop.sh | iex

# Install tools
scoop install git nvm
scoop bucket add extras
scoop install docker
```

### Initial Setup

#### 1. Clone Repository

```bash
git clone https://github.com/statisticsnorway/statbus.git
cd statbus
```

#### 2. Configure Git

**Set hooks path** (enforces conventions):
```bash
git config core.hooksPath .githooks
```

**Configure line endings** (critical for cross-platform):
```bash
git config --global core.autocrlf true
```

This project uses LF line endings. Git on Windows may convert to CRLF, which breaks scripts.

#### 3. Build CLI Tool

Build the StatBus CLI tool for database migrations:

```bash
cd cli && go build -o ../sb .
```

This compiles the Go CLI tool to `./sb`.

#### 4. Create User Configuration

```bash
cp .users.example .users.yml
```

Edit `.users.yml` to add your development users:
```yaml
users:
  - email: dev@example.com
    password: devpassword
    role: admin_user
```

#### 5. Generate Configuration

```bash
./sb config generate
```

This creates `.env`, `.env.credentials`, and `.env.config` with development defaults.

#### 6. Install Node.js

```bash
# Use Node version from .nvmrc
cd app
nvm install
nvm use

# Install pnpm globally
npm install -g pnpm

# Install app dependencies
pnpm install
```

---

## Project Structure

```
statbus/
├── app/                    # Next.js frontend application
│   ├── src/               # Source code
│   ├── public/            # Static assets
│   ├── package.json       # Node dependencies
│   └── CONVENTIONS.md     # Frontend conventions
├── cli/                   # Crystal CLI tool
│   ├── src/              # CLI source code
│   └── bin/              # Compiled binaries
├── ops/                  # Operations scripts
│   └── maintenance/      # Maintenance page
├── .githooks/            # Git hooks
├── doc/                  # Documentation
│   ├── integration/      # API & PostgreSQL guides
│   ├── deployment/       # Deployment guides
│   └── service-architecture.md
├── migrations/           # Database migrations
├── test/                # Database tests
│   ├── sql/            # Test SQL files
│   └── expected/       # Expected output
├── postgres/           # PostgreSQL configuration
├── caddy/             # Caddy configuration
├── rest/              # PostgREST configuration
├── worker/            # Background worker (Crystal)
├── .env.config        # Deployment configuration (edit this)
├── .env.credentials   # Generated credentials (don't edit)
├── .env               # Generated environment (don't edit)
├── CONVENTIONS.md     # Backend coding conventions
├── AGENTS.md          # AI agent guide
└── README.md          # Gateway document
```

---

## Local Development Workflow

### Development Mode

In development mode, you run backend services in Docker and the Next.js app locally for hot-reload.

#### Start Backend Services

```bash
# Start PostgreSQL, PostgREST, Caddy, Worker
./sb start all_except_app

# Initialize database (first time only)
./dev.sh create-db
./sb users create
./sb migrate up
```

#### Run Next.js Locally

```bash
cd app
nvm use
pnpm install
pnpm run dev
```

Access the application:
- **Frontend**: http://localhost:3000
- **API via Caddy**: http://localhost:3010/rest/
- **Supabase Studio**: http://localhost:3001

#### Stop Services

```bash
./sb stop all
```

### PostgreSQL Access for Development

The development environment provides PostgreSQL access through Caddy's Layer4 TLS proxy.

**Quick Access**:
```bash
# Use helper script (recommended)
./sb psql

# Or connect manually
eval $(./sb config show --postgres)
psql
```

**Manual Connection**:
```bash
export PGHOST=local.statbus.org
export PGPORT=3024
export PGDATABASE=statbus_speed
export PGUSER=postgres
export PGPASSWORD=$(./sb dotenv -f .env get POSTGRES_ADMIN_PASSWORD)
export PGSSLNEGOTIATION=direct
export PGSSLMODE=require
export PGSSLSNI=1

psql
```

**Connection Details**:
- **Domain**: `local.statbus.org` (resolves to 127.0.0.1)
- **Port**: 3024 (from `CADDY_DB_PORT`)
- **Database**: `statbus_speed` (from `POSTGRES_APP_DB`)
- **TLS**: Self-signed internal CA
- **SSL Mode**: `require` (encrypted, no cert verification)

---

## Database Development

### Database Migrations

StatBus uses a versioned migration system with Crystal CLI.

**Create Migration**:
```bash
cd cli
./bin/statbus migrate new --description "add column to legal_unit"
```

This creates two files in `migrations/`:
- `YYYYMMDDHHmmSS_add_column_to_legal_unit.up.sql`
- `YYYYMMDDHHmmSS_add_column_to_legal_unit.down.sql`

**Apply Migrations**:
```bash
./cli/bin/statbus migrate up      # Apply all pending
./cli/bin/statbus migrate down    # Rollback last migration
./cli/bin/statbus migrate redo    # Rollback and re-apply last
```

**Migration Conventions**:
- Write idempotent migrations (can run multiple times)
- Always provide `down` migration for rollback
- Test migrations on sample data before committing
- See [CONVENTIONS.md](CONVENTIONS.md) for SQL style guide

### Database seed

A **seed** is a `pg_dump` of a fully-migrated, empty database. A fresh install or
dev box restores it in ~2 seconds instead of replaying every migration from zero,
then runs only the migrations newer than the seed. **Creating** the seed is a
developer/CI activity (documented here); **restoring** it is part of install — see
[Upgrade Timeline § Fresh-install seed restore](upgrade-timeline.md#fresh-install-seed-restore)
for where the restore enters the runtime.

#### Creating the seed

`./sb db seed dump` (`cli/cmd/seed.go:285`, core in `DumpSeed`, `cli/cmd/seed.go:379`)
writes two files into `.db-seed/` from the `statbus_seed` database:

- `.db-seed/seed.pg_dump` — `pg_dump -Fc --no-owner --exclude-table-data=auth.secrets <seed-db>`
  (`cli/cmd/seed.go:463`). Custom format (`-Fc`) so the consume side can `pg_restore`.
  `auth.secrets` data is excluded because it holds per-deployment JWT secrets that must
  never ship in a shared artifact (`cli/cmd/seed.go:447`).
- `.db-seed/seed.json` — the metadata sidecar (`cli/cmd/seed.go:490`).

`DumpSeed` dumps from `${POSTGRES_SEED_DB}` (the canonical fresh-from-migrations DB),
never from the runtime app DB, which is contaminable by definition (`cli/cmd/seed.go:376`).
It refuses to run if the DB is unreachable (`cli/cmd/seed.go:384`) or the seed DB does
not exist (`cli/cmd/seed.go:398`), pointing you at `./dev.sh recreate-seed`.

Build the seed DB itself with `./dev.sh recreate-seed` (`dev.sh:1326`): it fetches the
latest published seed, restores it, then applies only the newer migrations — the same
fast path the install uses. Under the hood that is the three primitives
`./sb db seed create-db` (a fresh copy of `template_statbus` plus the per-DB `auth`
schema and grants — `CreateSeedDb`, `cli/cmd/seed.go:313`) → `./sb migrate up --target seed`
→ `./sb db seed dump`. `FULL_REPLAY=1 ./dev.sh recreate-seed` forces a from-zero rebuild.

#### seed.json fields

`seedMeta` (`cli/cmd/seed.go:37`) — written at creation, read on the consume side:

| Field | Source | Read at restore for |
|---|---|---|
| `migration_version` | `MAX(version)` from `db.migration` (`cli/cmd/seed.go:406`) | the schema state the dump captures; `migrate up` applies only newer versions |
| `post_restore_sha` | sha256 of `migrations/post_restore.sql` (`postRestoreFileSHA`, `cli/cmd/seed.go:526`) | the freshness fingerprint (below) |
| `commit_sha` | `git rev-parse HEAD`, or `--commit` when there is no `.git` (`cli/cmd/seed.go:421`) | which commit the seed belongs to |
| `tags` | `git tag --points-at HEAD` (`cli/cmd/seed.go:425`) | release tags at that commit (empty in the image build) |
| `created_at` | UTC RFC3339 timestamp (`cli/cmd/seed.go:495`) | human freshness display |

These fields are consumed on the restore side — see
[Upgrade Timeline § Fresh-install seed restore](upgrade-timeline.md#fresh-install-seed-restore).

#### The post_restore.sql fingerprint

`migrations/post_restore.sql` is re-run on **every** `migrate up`, even when no new
migrations are pending (`cli/internal/migrate/migrate.go:756`, applied at `:912`). So an
edit to `post_restore.sql` changes the post-restore schema state **without** bumping any
migration version — and without a fingerprint that change would silently ship a stale
dump. Recording the file's sha256 in `seed.json` (`cli/cmd/seed.go:437`) makes the change
detectable even when `migration_version` is unchanged; an absent field is treated as
"fingerprint missing → full rebuild" (`cli/cmd/seed.go:28`).

#### CI packs the seed into a commit-tagged image

The seed ships as the OCI image `ghcr.io/statisticsnorway/statbus-seed:<commit_short>` —
the same commit-addressable transport as the five service images, replacing the former
`db-seed` git branch. The `seed` job in `.github/workflows/images.yaml:129` builds it
`--target seed` from `postgres/Dockerfile` **after** the `statbus-sb` manifest exists (it
is pulled in as a build-context), passing the full `COMMIT` SHA so `seed.json` carries the
right commit when the build tree has no `.git`. It is amd64-only because the `-Fc` logical
dump restores onto either architecture.

Inside the image build, the hermetic `seed-builder` stage (`postgres/Dockerfile:452`) runs
the real `sb` subcommands — `sb db seed create-db` → `sb migrate up --target seed` →
`sb db seed dump --commit $COMMIT` (`postgres/Dockerfile:513`) — so there is zero
hand-mirrored SQL. The final `seed` stage is `busybox:musl` and ships both `/seed.pg_dump`
and `/seed.json` with a self-documenting `CMD` (`postgres/Dockerfile:534`); `docker run` on
it prints extraction usage rather than starting a service.

### Database Schema

StatBus uses several PostgreSQL schemas:

- **public**: Main application tables (legal_unit, establishment, etc.)
- **admin**: Administrative tables (users, settings)
- **auth**: Authentication functions and JWT handling
- **db**: Views and helper functions
- **lifecycle_callbacks**: Triggers and validation logic

### Testing Database Changes

**Run pg_regress tests**:
```bash
# Run all tests
./dev.sh test all

# Run specific test
./dev.sh test 015_my_test

# Run failed tests only
./dev.sh test failed
```

Test files location:
- SQL: `test/sql/*.sql`
- Expected output: `test/expected/*.out`

**Create a new test**:
```bash
# Create SQL test file
echo "SELECT 'test output';" > test/sql/999_my_test.sql

# Run it to generate expected output
./dev.sh test 999_my_test

# If correct, copy output
cp test/regression.out test/expected/999_my_test.out
```

### Generate TypeScript Types

After changing database schema, regenerate TypeScript types:

```bash
./sb types generate
```

This updates `app/src/lib/database.types.ts` with current schema.

### Direct Database Access

**Run SQL file**:
```bash
./sb psql < my_script.sql
```

**Run SQL command**:
```bash
echo "SELECT * FROM auth.users LIMIT 5;" | ./sb psql
```

**Interactive psql**:
```bash
./sb psql
```

---

## Frontend Development

### Next.js Application

The frontend is built with:
- **Next.js 15** (App Router)
- **React 18** with TypeScript
- **Tailwind CSS** for styling
- **shadcn/ui** component library
- **Jotai** for state management

### Development Server

```bash
cd app
pnpm run dev        # Start dev server with Turbopack
```

The dev server runs on **http://localhost:3000** with:
- Hot module replacement
- TypeScript checking
- Fast refresh

### Important Scripts

```bash
cd app

# Development
pnpm run dev           # Start dev server
pnpm run build         # Production build
pnpm run start         # Start production server

# Code Quality
pnpm run lint          # ESLint
pnpm run format        # Check Prettier
pnpm run format:fix    # Fix Prettier issues
pnpm run tsc           # Type check

# Testing
pnpm run test          # Run Jest tests
pnpm run test:watch    # Watch mode
```

### State Management with Jotai

**Critical Rules**:
- Small, independent atoms prevent re-render loops
- If state can change independently, it MUST be in its own atom
- Use `atomEffect` for set-if-null patterns, NOT `useEffect`
- Variables match atom names: `const timeContext = useAtomValue(timeContextAtom)`

**Use Guarded Effects**:
```typescript
import { useGuardedEffect } from '@/lib/use-guarded-effect';

// ALL effects MUST use useGuardedEffect
useGuardedEffect(callback, deps, 'FileName.tsx:purpose');
```

See [app/CONVENTIONS.md](app/CONVENTIONS.md) for detailed frontend conventions.

### API Request Flow

**Development Mode** (`pnpm run dev` on host):
1. Browser accesses `http://localhost:3000`
2. Client makes API calls to `/rest/*`
3. Next.js dev server proxies to Caddy (`http://localhost:3010/rest/*`)
4. Caddy handles auth cookie conversion
5. Caddy proxies to PostgREST

**Production Mode** (Docker):
1. Browser accesses `https://statbus.example.com`
2. Client makes API calls directly to Caddy `/rest/*`
3. Caddy handles auth and proxies to PostgREST

---

## Code Conventions

### Backend (SQL/PostgreSQL)

See [CONVENTIONS.md](CONVENTIONS.md) for full details.

**Key patterns**:

**Function Definitions**:
```sql
CREATE FUNCTION auth.jwt_verify(token_value text)
RETURNS auth.jwt_verify_result
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth, pg_temp
AS $jwt_verify$
DECLARE
  _jwt_verify_result auth.jwt_verify_result;
BEGIN
  -- Function body
END;
$jwt_verify$;
```

**Naming Conventions**:
- `x_id` = foreign key to table x
- `x_ident` = external identifier (not from DB)
- `x_at` = TIMESTAMPTZ
- `x_on` = DATE

**Temporal Logic**:
```sql
-- Chronological order: start <= point AND point < end
WHERE valid_from <= current_date AND current_date < valid_to
```

### Frontend (TypeScript/React)

See [app/CONVENTIONS.md](app/CONVENTIONS.md) for full details.

**Import Style**:
```typescript
import { NextRequest, NextResponse } from "next/server";
import { getServerRestClient } from "@/context/RestClientStore";
```

**Named Exports** (preferred over default exports):
```typescript
export const MyComponent = () => { ... };
export function myFunction() { ... }
```

### Git Commit Messages

Format: `prefix: description`

**Prefixes**:
- `feat:` - New feature
- `fix:` - Bug fix
- `docs:` - Documentation
- `refactor:` - Code refactoring
- `test:` - Test changes
- `chore:` - Build/tooling changes

**Examples**:
```
feat: Add temporal foreign key validation
fix: JWT verification with expired tokens
docs: Update PostgreSQL connection guide
```

---

## Testing

### Backend Tests (pg_regress)

```bash
# Run all tests
./dev.sh test all

# Run specific test
./dev.sh test 015_jwt_auth

# Run multiple tests
./dev.sh test 015_jwt_auth 020_temporal

# Exclude tests
./dev.sh test all -010_old_test

# Run failed tests
./dev.sh test failed
```

### Frontend Tests (Jest)

```bash
cd app
pnpm run test           # Run once
pnpm run test:watch     # Watch mode
pnpm run test:coverage  # With coverage
```

### Upgrade System Hardening Tests

To verify the upgrade service's rollback and recovery mechanisms, use these procedures. Each requires tagging deliberate broken RCs, then fixing them.

**Test 1: Broken migration → database rollback**

1. Create a migration that fails (e.g., `SELECT 1/0;`)
2. Optionally add a preceding migration that creates a marker table (to verify both are rolled back)
3. Tag as a pre-release RC
4. Apply on a test server: `./sb upgrade apply <broken-rc>`
5. Verify: migration fails, service rolls back, marker table is gone, upgrade shows "rolled back"
6. Tag a fix RC that removes the broken migrations
7. Apply the fix RC: verify it applies cleanly, binary self-updates

**Test 2: Broken binary → self-verify rejection**

1. Add `os.Exit(1)` to `upgradeSelfVerifyCmd` in `cli/cmd/upgrade.go`
2. Tag as a pre-release RC
3. Apply on a test server: the upgrade succeeds (migrations, health check) but self-verify fails
4. Verify: old binary is kept, service logs the failure, system continues running
5. Tag a fix RC that removes the `os.Exit(1)`
6. Apply the fix RC: verify binary self-updates successfully

**What these tests exercise:**
- Database rollback via rsync restore (Test 1)
- Binary self-update rejection on verify failure (Test 2)
- Version skipping: the fix RC supersedes the broken RC
- Service recovery: continues operating after failures

---

## Architecture

### Service Architecture

StatBus consists of five main services:

1. **PostgreSQL**: Database with Row Level Security and temporal tables
2. **PostgREST**: Automatic REST API from database schema
3. **Caddy**: Reverse proxy, auth gateway, and PostgreSQL TLS proxy
4. **Next.js**: Server-side rendered web application
5. **Worker**: Background job processor (Crystal)

See [doc/service-architecture.md](doc/service-architecture.md) for detailed architecture.

### Authentication Flow

1. User logs in via `/rest/rpc/login` (handled by PostgreSQL function)
2. JWT tokens stored in cookies (`statbus` and `statbus-refresh`)
3. Caddy extracts JWT from cookies and adds Authorization headers
4. PostgREST validates JWT and sets database role
5. Row Level Security enforces access control

### PostgreSQL Layer4 TLS Proxy

Caddy provides secure direct PostgreSQL access:

**Development Architecture**:
```
psql → local.statbus.org:3024 (TLS+SNI)
  → Caddy (terminates TLS)
    → db:5432 (Docker network)
```

**Benefits**:
- TLS encryption without PostgreSQL TLS configuration
- SNI-based routing for multi-tenant deployments
- Standard tools (psql, pgAdmin, DBeaver) work seamlessly

See [doc/service-architecture.md#postgresql-access-architecture](doc/service-architecture.md#postgresql-access-architecture) for details.

---

## Development Tips

### Scratch Directories

Use `tmp/` for development experiments:
- `tmp/` - Backend scratch (SQL, scripts)
- `app/tmp/` - Frontend scratch (TypeScript, configs)

These directories are gitignored but a pre-commit hook prevents accidental commits.

### Debugging

**Backend Logs**:
```bash
docker compose logs -f db      # PostgreSQL
docker compose logs -f rest    # PostgREST
docker compose logs -f proxy   # Caddy
docker compose logs -f worker  # Background worker
```

**Frontend Debugging**:
- Use Chrome DevTools
- React DevTools extension
- Next.js built-in error overlay

**Database Debugging**:
```sql
-- Enable query logging
ALTER DATABASE statbus_speed SET log_statement = 'all';

-- View recent queries
SELECT * FROM pg_stat_statements;
```

### Code Quality

**Before committing**:
```bash
# Backend
./dev.sh test all

# Frontend
cd app
pnpm run lint
pnpm run format
pnpm run tsc
pnpm run test
```

### Working with AI Agents

See [AGENTS.md](AGENTS.md) for guidance on using AI coding assistants with StatBus.

---

## Getting Help

### Documentation

- **[User Guide](USAGE.md)**: For end users
- **[Deployment Guide](DEPLOYMENT.md)**: For administrators deploying single instance
- **[Cloud Guide](CLOUD.md)**: For SSB staff managing multi-tenant cloud
- **[Service Architecture](doc/service-architecture.md)**: Technical details
- **[Integration Guide](INTEGRATE.md)**: API and PostgreSQL
- **[Conventions](CONVENTIONS.md)**: Backend coding standards
- **[App Conventions](app/CONVENTIONS.md)**: Frontend coding standards

### Community

- **Issues**: https://github.com/statisticsnorway/statbus/issues
- **Discussions**: https://github.com/statisticsnorway/statbus/discussions
- **Website**: https://www.statbus.org

### Contributing

1. Fork the repository
2. Create a feature branch (`git checkout -b feat/my-feature`)
3. Make your changes following conventions
4. Write/update tests
5. Commit with conventional commit messages
6. Push and create a Pull Request

Thank you for contributing to StatBus!
