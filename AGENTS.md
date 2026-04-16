# AI Agent Guide for STATBUS

This guide is for AI coding assistants working in the STATBUS codebase. STATBUS is a statistical business registry with temporal tables for tracking business activity throughout history. Built by Statistics Norway (SSB) using PostgreSQL 18+, PostgREST 12+, and Next.js 15+.

**Architecture**: Database-centric progressive disclosure (NOT microservices). PostgreSQL IS the backend—PostgREST exposes the schema directly. Security happens entirely at the database layer via Row Level Security (RLS).

## Quick Commands

StatBus has two command-line tools:
- **`./sb`** — Go CLI for ops/production commands (start, stop, psql, migrate, upgrade, etc.)
- **`./dev.sh`** — Bash script for development-only commands (test, create-db, etc.)

The legacy `manage-statbus.sh` has been deleted. All references should use `./sb` or `./dev.sh` instead.

### Operations (./sb)
```bash
# Service management (profiles: all, all_except_app, app)
./sb start all                  # Start all services (db, rest, worker, app)
./sb stop all                   # Stop all services
./sb restart all                # Restart all services
./sb ps                         # List running containers
./sb logs [service...]          # Follow service logs
./sb build [profile]            # Build Docker images from source (development only)

# Database connection
./sb psql                       # Open psql shell
./sb psql < file.sql            # Run SQL file (use < redirection!)
echo "SELECT ..." | ./sb psql   # Single-line query

# Configuration
./sb config generate            # Regenerate .env and Caddyfiles from .env.config
./sb config show                # Show current config (verbose)
./sb config show --postgres     # Print shell-evaluable PG vars: eval $(./sb config show --postgres)

# Environment files
./sb dotenv -f .env get KEY            # Read a key from .env file
./sb dotenv -f .env set KEY VALUE      # Set a key (also accepts KEY=VALUE)
./sb dotenv -f .env set KEY +DEFAULT   # Set only if key doesn't exist

# Users and types
./sb users create               # Create users from .users.yml
./sb types generate             # Generate TypeScript types from schema

# Database operations
./sb db status                  # Check if database is running
./sb db dump                    # Dump local database to dbdumps/
./sb db download <code>         # Download database dump from remote server
./sb db dumps list              # List available database dumps
./sb db dumps purge [N]         # Delete old dumps, keeping newest N per source
./sb db restore <file>          # Restore dump to local database
./sb db restore <file> --to no  # Restore dump to remote server
```

### Database Inspection Patterns
```bash
echo "\d tablename" | ./sb psql           # Table structure
echo "\dt pattern*" | ./sb psql           # Find tables by pattern
echo "\dv viewname" | ./sb psql           # View definition
echo "SELECT ..." | ./sb psql             # Single queries
```

**Offline inspection via `doc/db/`**: The `doc/db/` directory contains dumps of all database functions, tables, and views in markdown format. Use `grep` / `rg` on these files when you need to search function bodies without a running database. Prefer this over grepping `migrations/` — migrations are chronological, so the first match is the oldest and least relevant version.

### Testing (./dev.sh)
```bash
./dev.sh test fast 2>&1 | tee tmp/test-fast.log         # Run fast tests only (good for quick iteration)
./dev.sh test 015_my_test                                # Run single test (prefix number)
./dev.sh test 300_test 2>&1 | tee tmp/test-300_test.log  # Save output to log file for later review
./dev.sh diff-fail-all pipe                              # Show diffs for all failed tests
./dev.sh test all                                        # Run all pg_regress tests (EXTREMELY SLOW)

# IMPORTANT: Use tee to save output - prevents wasting time re-running slow tests
# Test results are in test/results/*.out and can be compared to test/expected/*.out
```

**⚠️ DESTRUCTIVE Operations (LOCAL DEVELOPMENT ONLY - NEVER IN PRODUCTION):**
```bash
./dev.sh create-db           # Create database with migrations
./dev.sh delete-db           # ⚠️ DESTROYS ALL DATA
./dev.sh delete-db-structure # ⚠️ Drops schema, keeps container
./dev.sh recreate-database   # ⚠️ Delete + Create (fresh start)
```

### Migrations (./sb)
```bash
./sb migrate new --description "my change"  # Create migration
./sb migrate up                             # Apply migrations
./sb migrate down                           # ⚠️ Rollback (destructive)
```

### Install / Upgrade (./sb)
```bash
./sb install                      # Unified entrypoint — detects state and dispatches
./sb upgrade check                # Check GitHub for new releases
./sb upgrade list                 # List discovered upgrades from database
./sb upgrade schedule <version>   # Queue an upgrade (writes a public.upgrade row)
./sb upgrade apply <version>      # Trigger immediate upgrade via NOTIFY (needs running service)
./sb upgrade service              # Run upgrade service (usually via systemd)
./sb upgrade recover              # One-shot: reconcile a crashed upgrade flag
```

`./sb install` is the single operator-facing entrypoint for first-install, repair, and applying a pending upgrade without waiting for the service. On each run it probes install state and dispatches:

| Detected state                     | Action                                                                                  |
|------------------------------------|-----------------------------------------------------------------------------------------|
| fresh (no `.env.config`)           | Run the step-table to set up a clean install                                            |
| half-configured / DB unreachable   | Run the step-table to repair / continue setup                                           |
| nothing-scheduled                  | Run the step-table as an idempotent config refresh                                      |
| scheduled-upgrade                  | Dispatch the pending `public.upgrade` row through the same pipeline the service uses    |
| crashed-upgrade (stale flag + dead PID) | Reconcile the flag, re-detect, re-dispatch                                         |
| live-upgrade (service running)     | Refuse with diagnostic; do not touch state                                              |
| legacy pre-1.0 (no `public.upgrade` table) | Refuse with pointer to manual upgrade path (`doc/CLOUD.md`)                     |

Canonical operator upgrade workflow: `./sb upgrade schedule <version>` to queue, then either wait for the service's next tick (production norm) or run `./sb install` to dispatch immediately. After a successful inline upgrade the systemd upgrade unit (if active) is restarted so it picks up the new binary + migrations. Full contract in `doc/upgrade-system.md` and `doc/install-mutex.md`.

**Migration Best Practice for Modifying Existing Functions/Procedures:**

When modifying an existing database function or procedure, **always dump the current definition first** rather than rewriting from scratch:

```bash
# Dump function definition to use as base for both up and down migrations
echo "\sf schema.function_name" | ./sb psql > tmp/function_def.sql

# For procedures
echo "\sf schema.procedure_name" | ./sb psql > tmp/procedure_def.sql
```

Then:
1. cat the dumped definition into the **down migration** (this restores the original)
2. cat it into the **up migration**
3. Add `CREATE OR REPLACE` prefix and wrap in `BEGIN;`/`END;`
4. Stage the up/down migration.
5. Make only the necessary modifications in the up migration - noe easy to review as unstaged changes.

This approach:
- Preserves exact current behavior in the down migration
- Ensures surgical changes rather than accidental rewrites
- Reduces risk of introducing bugs from manual recreation
- Maintains all edge cases, exception handling, and comments

**CRITICAL**: Never rewrite large functions/procedures from scratch. The `\sf` dump ensures you're modifying the *actual current code*, not an outdated or incomplete version. For large procedures (100+ lines), focus only on the specific lines that need changing.

### Next.js Application (from app/ directory)
```bash
cd app && pnpm run dev          # Development server with Turbopack
cd app && pnpm run build        # Production build
cd app && pnpm run lint         # ESLint
cd app && pnpm run format       # Check Prettier
cd app && pnpm run format:fix   # Fix Prettier issues
cd app && pnpm run tsc          # Type check without emit
cd app && pnpm run test         # Run Jest tests
```

## Deployment Architecture

### Deployment Modes vs. Deployment Slots

**CRITICAL**: These are two SEPARATE concepts that control different aspects:

#### Deployment MODES (Caddy behavior)

Controlled by `CADDY_DEPLOYMENT_MODE` - defines **how Caddy operates**:

- **`development`**: Local development
  - HTTP only, self-signed internal CA certs
  - Next.js runs separately on host (`pnpm run dev`) at port 3000 (http://local.statbus.org:3000)
  - Slot-based ports (e.g., 3010) are for testing containerized production builds to catch advanced timing issues
  - PostgreSQL available on two separate ports (slot-based):
    - Port 3014 (offset 1): Plaintext (default, convenient for local psql and SSH tunnels)
    - Port 3015 (offset 1): TLS+SNI (for testing production-like connections with `TLS=1`)

- **`standalone`**: Single-server production
  - HTTPS with automatic Let's Encrypt certificates
  - All services run in Docker
  - Standard ports: 443 (HTTPS), 5432 (PostgreSQL)
  - Direct public access, no additional proxy needed
  - Public domain required (e.g., `statbus.example.com`)

- **`private`**: Behind host-level reverse proxy (multi-tenant cloud)
  - HTTP only (host-level proxy handles HTTPS)
  - Trusts X-Forwarded-* headers from proxy
  - Multiple instances on same host with unique ports
  - PostgreSQL: plaintext (SSH tunnel provides encryption)

#### Deployment SLOTS (Instance isolation)

Controlled by `DEPLOYMENT_SLOT_CODE` and `DEPLOYMENT_SLOT_PORT_OFFSET` - enables **multiple instances per host**:

- Each slot = separate instance (country/environment)
- Port calculation: `3000 + (slot_offset × 10)`
  - Offset 1 (local): 3010 (HTTP), 3011 (HTTPS), 3012 (app), 3013 (rest), 3014 (db), 3015 (db-tls)
  - Offset 2 (ma): 3020 (HTTP), 3021 (HTTPS), 3022 (app), 3023 (rest), 3024 (db), 3025 (db-tls)
  - Offset 3 (no): 3030 (HTTP), 3031 (HTTPS), 3032 (app), 3033 (rest), 3034 (db), 3035 (db-tls)

- Slot code used in:
  - Container names: `statbus-{code}-app`, `statbus-{code}-db`
  - Database names: `statbus_{code}`
  - Cookie names: `statbus-{code}`, `statbus-{code}-refresh`
  - Subdomains: `{code}.statbus.org`

### PostgreSQL Connection Patterns

**Note:** `./sb migrate up` and other server-internal database clients should use `CADDY_DB_BIND_ADDRESS` + `CADDY_DB_PORT` (loopback in private mode), NOT `SITE_DOMAIN`. `SITE_DOMAIN` is the external hostname used via SSH tunnel (private) or public DNS (standalone); Caddy does not expose the DB port on that address in private-mode deployments.

**Local Development** (mode=development):
```bash
# Default: plaintext on slot-based port (e.g., 3014 for local slot)
./sb psql -c "SELECT version();"

# Testing TLS: uses TLS port (e.g., 3015 for local slot) with SNI
TLS=1 ./sb psql -c "SELECT version();"
```

**Remote via SSH Tunnel** (mode=private):
```bash
# SSH tunnel: local:3014 → remote:127.0.0.1:3014 → db:5432
# Plaintext through tunnel (SSH provides encryption)
ssh statbus_dev@statbus.org "cd statbus && ./sb psql"
```

**Production** (mode=standalone):
```bash
# Direct public access with TLS via Caddy Layer4 proxy
export PGHOST=statbus.example.com
export PGPORT=5432
export PGSSLMODE=require
export PGSSLNEGOTIATION=direct
export PGSSLSNI=1
psql
```

### Key Configuration Files

- `cli/src/manage.cr`: Configuration generation and port calculation logic
- `cli/src/templates/*.caddyfile.ecr`: Mode-specific Caddy templates
- `sb`: Go CLI binary (built from cli/, in .gitignore)
- `dev.sh`: Development-only commands (test, create-db, etc.)
- `ops/`: Operations scripts (maintenance, notifications, service files)
- `.env.config`: **Edit this** for deployment settings
- `.env`: Generated file, **do not edit** directly
- `.env.credentials`: Secrets, generated once, keep secure

### Cloud Multi-Tenant Deployment

The cloud infrastructure on **niue.statbus.org** uses **branches as pointers** for CI/CD. See `doc/CLOUD.md` for full details.

1. **Trigger deployment** (GitHub Actions -> "Run workflow"):
   - `master-to-X` workflow force-pushes `master` -> `ops/cloud/deploy/X` branch
   - Example: "Push master -> ops/cloud/deploy/no" deploys to Norway

2. **Automatic execution**: Push to `ops/cloud/deploy/X` triggers `deploy-to-X` workflow, which SSHs to the server and triggers the upgrade service

3. **On the server** (upgrade service):
   - CLI writes upgrade request to database and sends NOTIFY
   - The upgrade service backs up the database
   - Checks out the target version
   - Runs pending migrations (or recreates if --recreate)
   - Restarts services with health checks
   - Rolls back automatically on failure
   - Sends callback notification (Slack)

#### Deployment Targets

| Workflow | Branch | Server | Notes |
|----------|--------|--------|-------|
| master-to-no | ops/cloud/deploy/no | statbus_no@niue | Norway |
| master-to-demo | ops/cloud/deploy/demo | statbus_demo@niue | Demo |
| master-to-dev | ops/cloud/deploy/dev | statbus_dev@niue | Development |
| master-to-production | ops/cloud/deploy/production | — | Pointer only |
| production-to-all | — | all servers | Cascades to all |

#### Triggering Deployment

```bash
git push origin master:ops/cloud/deploy/no         # Deploy master to Norway
git push origin master:ops/cloud/deploy/dev        # Deploy master to dev
```

This directly updates the branch pointer, which triggers `deploy-to-X.yaml`. The `master-to-X` workflows in GitHub UI do the same thing but add an extra hop.

#### Manual Server Access

```bash
ssh statbus_no "cd statbus && <command>"           # Run command on server
scp local/file statbus_no:statbus/path/to/file     # Copy file to server
```

**Before deploying**: Ensure remote working directory is clean (no uncommitted changes), or deploy will fail.

## Project Structure

- `migrations/` - Database migrations (YYYYMMDDHHmmSS_description.up.sql/.down.sql)
- `app/` - Next.js 15 application (App Router, TypeScript, Tailwind, shadcn/ui)
- `cli/` - Crystal CLI tool for migrations and database management
- `test/sql/` - pg_regress SQL tests with expected output in `test/expected/`
- `ops/` - Operations scripts (maintenance, notifications, service files)
- `doc/` - Architecture and design documentation

## Critical Conventions

### SQL (See `.claude/rules/sql.md` for full details)

**Function Definitions:**
```sql
CREATE FUNCTION auth.jwt_verify(token_value text)
RETURNS auth.jwt_verify_result
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth, pg_temp
AS $jwt_verify$
DECLARE
  _jwt_verify_result auth.jwt_verify_result;  -- Variable matches type name
BEGIN
  -- Function body
END;
$jwt_verify$;
```

**Key patterns:**
- Use function name in dollar quotes: `AS $function_name$`
- Variables match their type names: `_jwt_verify_result auth.jwt_verify_result`
- Related functions share prefixes: `jwt_verify()`, `jwt_switch_role()`, `jwt_secret()`
- Format strings use dollar quotes: `format($$SELECT %I$$, table_name)`
- Temporal logic: chronological order `start <= point AND point < end`
- Table aliases: explicit `AS`, e.g., `FROM my_table AS mt`

**Naming:**
- `x_id` = foreign key to table `x`
- `x_ident` = external identifier (not from DB)
- `x_at` = TIMESTAMPTZ
- `x_on` = DATE

### TypeScript/Next.js (See `.claude/rules/frontend.md` for full details)

**Imports:**
```typescript
import { NextRequest, NextResponse } from "next/server";
import { getServerRestClient } from "@/context/RestClientStore";
import { Pool } from 'pg';
```
- Use `@/` for absolute imports from `app/src/`
- Named exports preferred over default exports

**API Architecture:**
- **CRITICAL**: Prefer direct browser-to-`/rest` requests over Next.js `/api` routes
- Why: Easier debugging, enables user integration, transparency, better performance
- Direct `/rest` shows actual database requests/responses (PostgREST)
- Users can learn API patterns from browser Network tab for their own integrations
- Security: JWT tokens map to database roles—NO server-side secrets typically needed
- Only use `/api` routes for performance optimizations (e.g., bulk upload via COPY) or webhooks

**State Management (Jotai):**
- **CRITICAL**: Small, independent atoms prevent re-render loops
- If state can change independently, it MUST be in its own atom
- Use `atomEffect` for set-if-null patterns, NOT `useEffect`
- Variables match atom names: `const timeContext = useAtomValue(timeContextAtom)`

**Effects:**
- ALL effects MUST use `useGuardedEffect` instead of `useEffect`
- Format: `useGuardedEffect(callback, deps, 'FileName.tsx:purpose')`
- State machine effects: depend on primitives, not whole state object

**Database Types:**
- Generated via `./sb types generate`
- Located in `app/src/lib/database.types.ts`
- Use: `Tables<'my_table'>`, `Enums<'my_enum'>`

## Performance Optimization Workflow

When optimizing slow database queries:

1. **Enable DEBUG mode** in `.env.config` to get auto_explain logs for queries >100ms
2. **Preserve test databases** with `PERSIST=true` for investigation while tests run
3. **Don't start long-running tests** without first preparing hot-patches for iteration
4. **Analyze auto_explain logs** for:
   - "Rows Removed by Filter/Join Filter" - high numbers indicate inefficient joins
   - Nested loops with large row counts - may need indexes or query restructuring
   - Sequential scans on large tables - may need indexes
5. **Hot-patch for quick iteration**: Use `CREATE OR REPLACE FUNCTION` directly in psql to test changes without full migration/test cycles
6. **Common patterns**:
   - LATERAL JOIN → CTE + regular JOIN for batch operations (O(n²) → O(n))
   - `IS NOT DISTINCT FROM` with NULLs → COALESCE with sentinels for hash joins
   - Missing indexes → check if query patterns match existing indexes

**Key commands for performance analysis:**
```bash
# View auto_explain logs (queries >100ms)
docker compose logs db 2>&1 | grep -E "duration: [0-9]{5,}" | head -30

# Find queries with high row removal (inefficient joins)
docker compose logs db 2>&1 | grep -E "Rows Removed by (Join )?Filter:" | sort | uniq -c | sort -rn | head -20

# Check task timings in worker
echo "SELECT command, COUNT(*), SUM(duration_ms)::numeric(10,0) as total_ms FROM worker.tasks WHERE state = 'completed' GROUP BY command ORDER BY total_ms DESC;" | ./sb psql
```

## Development Workflow (CRITICAL)

Follow this iterative cycle for ALL changes, especially bug fixes:

1. **Hypothesize**: State hypothesis in `tmp/journal.md` (use for thought process, not tracked by OpenCode)
2. **Plan**: Use TodoWrite tool to create tasks for multi-step work (OpenCode tracks these)
3. **Isolate**: Create/identify reproducing test
4. **Prototype**: Create non-destructive verification in `tmp/verify_fix.sql`
5. **Observe**: Run prototype, gather evidence (MANDATORY)
6. **Analyze**: If successful → proceed. If not → return to step 1
7. **Implement**: Propose permanent changes only after prototype succeeds
8. **Validate**: Run full test suite
9. **Complete**: Mark todos as completed using TodoWrite

**Never skip the prototype step.** A hypothesis is not confirmed until supported by direct observation.

### Task Management with TodoWrite

- Use TodoWrite for multi-step tasks (3+ steps or complex work)
- Mark tasks as `in_progress` when starting, `completed` when done
- Only ONE task should be `in_progress` at a time
- Example: `todowrite({ todos: [{ id: "1", content: "Fix JWT verification", status: "in_progress", priority: "high" }] })`

## Key Tools

- `rg` (ripgrep) - Primary search tool
- `tree` - Directory structure
- `head` - Inspect file beginnings
- `ls` - Check file sizes
- `ruplacer` - Large-scale find/replace
- `renamer` - Batch renaming

## Security Model

- JWT secret stored in `auth.secrets` table with RLS
- `SECURITY DEFINER` functions bypass RLS (can access secrets)
- `SECURITY INVOKER` functions inherit caller privileges (can use `SET ROLE`)
- Pattern: verification (DEFINER) separated from role switching (INVOKER)

## Error Handling

**Fail Fast**: Code expected to work should fail immediately with clear errors. Don't mask problems.

**Example:**
```sql
IF _jwt_verify_result.is_valid = FALSE THEN
  RAISE EXCEPTION 'Invalid token: %', _jwt_verify_result.error_message;
END IF;
```

**Testing: Avoid DO Blocks for Error Verification**

DO blocks that catch exceptions are **opaque** - they hide actual behavior. If an UPDATE affects 0 rows, no exception fires and the test silently "passes".

```sql
-- BAD: Hides that UPDATE matched 0 rows
DO $$ BEGIN
  UPDATE t SET x = 1 WHERE id = currval('seq');  -- Wrong id!
EXCEPTION WHEN check_violation THEN RAISE NOTICE 'Working'; END $$;

-- GOOD: Transparent - see actual errors, verify results
SAVEPOINT sp;
\set ON_ERROR_STOP off
UPDATE t SET x = 1 WHERE id = 1;  -- See actual ERROR
\set ON_ERROR_STOP on
ROLLBACK TO SAVEPOINT sp;
SELECT COUNT(*) FROM t WHERE x = 1;  -- Verify: 0
```

For deterministic tests: `DELETE FROM t; ALTER SEQUENCE t_id_seq RESTART WITH 1;`

## Common Patterns

**Temporal Table Cleanup:**
```sql
IF to_regclass('pg_temp.my_temp_table') IS NOT NULL THEN 
  DROP TABLE my_temp_table; 
END IF;
CREATE TEMP TABLE my_temp_table (...) ON COMMIT DROP;
```

**Async Action Atom:**
```typescript
export const loginAtom = atom(null, async (get, set, credentials) => {
  set(authStatusCoreAtom); // Trigger refresh
  await get(authStatusCoreAtom); // Wait for stable state
  // Now safe to navigate or react
});
```

## Notes

- Use `tmp/` directory for diagnostic SQL, journals, debug scripts (gitignored)
- Don't delete files from `tmp/` - they serve as useful logs
- Commit messages: `prefix: description` (e.g., `auth: Fix JWT verification`)
- For nested `format()`, use named dollar quotes: `$SQL$`, `$jsonb_expr$`

## Full Documentation

- **SQL Conventions (detailed)**: See `.claude/rules/sql.md`
- **Frontend Conventions (detailed)**: See `.claude/rules/frontend.md`
- **Multi-Agent Methodology**: See `doc/agentic-methodology.md` (for complex multi-phase tasks)
- **Data Model**: See `doc/data-model.md`
- **Authentication**: See `doc/auth-design.md`
- **Cloud Deployment**: See `doc/CLOUD.md` for multi-tenant on niue.statbus.org
- **Single-Instance Deployment**: See `doc/DEPLOYMENT.md` for standalone server setup
- **Import System**: See `doc/import-system.md`
- **Integration (API/PostgreSQL)**: See `doc/INTEGRATE.md`

## Engineering Principles

**Never defer known bugs.** If a latent bug is found during investigation, fix it immediately or in the very next step. Silent data corruption (e.g. missing UNIQUE constraints allowing duplicates) wastes huge amounts of user/debugging/support time. No "skip for now" — deferring known bugs is considered a moral deficiency.

**Always add constraints.** If a table can have duplicates that shouldn't exist, add `UNIQUE`. If a function has a race condition, fix it. The codebase has dozens of constraints by design — intentional quality engineering, not over-engineering.

**There are NO flaky tests.** Never dismiss test failures as "flaky" or "transient". Every failure has a real root cause. Common actual causes: concurrent test runs colliding on shared DB resources (left a background test running); actual code bugs introduced by changes; environment issues needing fixing. "Flaky" is a lazy excuse that masks real problems.
