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
git config core.hooksPath devops/githooks
```

**Configure line endings** (critical for cross-platform):
```bash
git config --global core.autocrlf true
```

This project uses LF line endings. Git on Windows may convert to CRLF, which breaks scripts.

#### 3. Build CLI Tool

Build the StatBus CLI tool for database migrations:

```bash
./devops/manage-statbus.sh build-statbus-cli
```

This compiles the Crystal CLI tool to `cli/bin/statbus`.

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
./devops/manage-statbus.sh generate-config
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
├── devops/               # Deployment scripts
│   ├── manage-statbus.sh # Main management script
│   └── githooks/         # Git hooks
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
./devops/manage-statbus.sh start all_except_app

# Initialize database (first time only)
./devops/manage-statbus.sh create-db-structure
./devops/manage-statbus.sh create-users
./cli/bin/statbus migrate up
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
./devops/manage-statbus.sh stop
```

### PostgreSQL Access for Development

The development environment provides PostgreSQL access through Caddy's Layer4 TLS proxy.

**Quick Access**:
```bash
# Use helper script (recommended)
./devops/manage-statbus.sh psql

# Or connect manually
eval $(./devops/manage-statbus.sh postgres-variables)
psql
```

**Manual Connection**:
```bash
export PGHOST=local.statbus.org
export PGPORT=3024
export PGDATABASE=statbus_speed
export PGUSER=postgres
export PGPASSWORD=$(./devops/dotenv --file .env get POSTGRES_ADMIN_PASSWORD)
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
./devops/manage-statbus.sh test all

# Run specific test
./devops/manage-statbus.sh test 015_my_test

# Run failed tests only
./devops/manage-statbus.sh test failed
```

Test files location:
- SQL: `test/sql/*.sql`
- Expected output: `test/expected/*.out`

**Create a new test**:
```bash
# Create SQL test file
echo "SELECT 'test output';" > test/sql/999_my_test.sql

# Run it to generate expected output
./devops/manage-statbus.sh test 999_my_test

# If correct, copy output
cp test/regression.out test/expected/999_my_test.out
```

### Generate TypeScript Types

After changing database schema, regenerate TypeScript types:

```bash
./devops/manage-statbus.sh generate-types
```

This updates `app/src/lib/database.types.ts` with current schema.

### Direct Database Access

**Run SQL file**:
```bash
./devops/manage-statbus.sh psql < my_script.sql
```

**Run SQL command**:
```bash
./devops/manage-statbus.sh psql -c "SELECT * FROM auth.users LIMIT 5;"
```

**Interactive psql**:
```bash
./devops/manage-statbus.sh psql
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
./devops/manage-statbus.sh test all

# Run specific test
./devops/manage-statbus.sh test 015_jwt_auth

# Run multiple tests
./devops/manage-statbus.sh test 015_jwt_auth 020_temporal

# Exclude tests
./devops/manage-statbus.sh test all -010_old_test

# Run failed tests
./devops/manage-statbus.sh test failed
```

### Frontend Tests (Jest)

```bash
cd app
pnpm run test           # Run once
pnpm run test:watch     # Watch mode
pnpm run test:coverage  # With coverage
```

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
./devops/manage-statbus.sh test all

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
