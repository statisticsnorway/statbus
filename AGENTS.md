# AI Agent Guide for STATBUS

This guide is for AI coding assistants working in the STATBUS codebase. STATBUS is a statistical business registry built with PostgreSQL 18+, PostgREST 12+, and Next.js 15+.

## Quick Commands

### Database Operations (Development Only)
```bash
./devops/manage-statbus.sh start all        # Start all services (db, rest, worker, app)
./devops/manage-statbus.sh psql             # Open psql shell
./devops/manage-statbus.sh psql < file.sql  # Run SQL file (use < redirection!)
echo "SELECT ..." | ./devops/manage-statbus.sh psql  # Single-line query
./devops/manage-statbus.sh generate-types   # Generate TypeScript types from schema
```

### Database Inspection Patterns
```bash
echo "\d tablename" | ./devops/manage-statbus.sh psql           # Table structure
echo "\dt pattern*" | ./devops/manage-statbus.sh psql           # Find tables by pattern
echo "\dv viewname" | ./devops/manage-statbus.sh psql           # View definition
echo "SELECT ..." | ./devops/manage-statbus.sh psql             # Single queries
```

**⚠️ DESTRUCTIVE Operations (LOCAL DEVELOPMENT ONLY - NEVER IN PRODUCTION):**
```bash
./devops/manage-statbus.sh create-db           # Create database with migrations
./devops/manage-statbus.sh delete-db           # ⚠️ DESTROYS ALL DATA
./devops/manage-statbus.sh delete-db-structure # ⚠️ Drops schema, keeps container
./devops/manage-statbus.sh recreate-database   # ⚠️ Delete + Create (fresh start)
```

### Docker Compose Operations
```bash
docker compose ps                    # List all services and their status
docker compose logs proxy            # View proxy (Caddy) logs
docker compose logs db --tail=100    # View last 100 lines of database logs
docker compose logs -f rest          # Follow PostgREST logs in real-time
docker compose restart proxy         # Restart specific service
docker compose exec db psql -U postgres -d statbus_local  # Direct psql access
```

### Testing
```bash
./devops/manage-statbus.sh test fast 2>&1 | tee tmp/test-fast.log         # Run fast tests only (good for quick iteration)
./devops/manage-statbus.sh test 015_my_test                               # Run single test (prefix number)
./devops/manage-statbus.sh test 300_test 2>&1 | tee tmp/test-300_test.log # Save output to log file for later review
./devops/manage-statbus.sh diff-fail-all pipe                             # Show diffs for all failed tests
./devops/manage-statbus.sh test all                                       # Run all pg_regress tests (EXTREMELY SLOW)

# IMPORTANT: Use tee to save output - prevents wasting time re-running slow tests
# Test results are in test/results/*.out and can be compared to test/expected/*.out
```

### Migrations
```bash
cd cli && ./bin/statbus migrate new --description "my change"  # Create migration
cd cli && ./bin/statbus migrate up                             # Apply migrations
cd cli && ./bin/statbus migrate down                           # ⚠️ Rollback (destructive)
```

**Migration Best Practice for Modifying Existing Functions/Procedures:**

When modifying an existing database function or procedure, **always dump the current definition first** rather than rewriting from scratch:

```bash
# Dump function definition to use as base for both up and down migrations
echo "\sf schema.function_name" | ./devops/manage-statbus.sh psql > tmp/function_def.sql

# For procedures
echo "\sf schema.procedure_name" | ./devops/manage-statbus.sh psql > tmp/procedure_def.sql
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

**Local Development** (mode=development):
```bash
# Default: plaintext on slot-based port (e.g., 3014 for local slot)
./devops/manage-statbus.sh psql -c "SELECT version();"

# Testing TLS: uses TLS port (e.g., 3015 for local slot) with SNI
TLS=1 ./devops/manage-statbus.sh psql -c "SELECT version();"
```

**Remote via SSH Tunnel** (mode=private):
```bash
# SSH tunnel: local:3014 → remote:127.0.0.1:3014 → db:5432
# Plaintext through tunnel (SSH provides encryption)
ssh statbus_dev@statbus.org "cd statbus && ./devops/manage-statbus.sh psql"
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
- `devops/manage-statbus.sh`: Management commands and helpers
- `.env.config`: **Edit this** for deployment settings
- `.env`: Generated file, **do not edit** directly
- `.env.credentials`: Secrets, generated once, keep secure

## Project Structure

- `migrations/` - Database migrations (YYYYMMDDHHmmSS_description.up.sql/.down.sql)
- `app/` - Next.js 15 application (App Router, TypeScript, Tailwind, shadcn/ui)
- `cli/` - Crystal CLI tool for migrations and database management
- `test/sql/` - pg_regress SQL tests with expected output in `test/expected/`
- `devops/` - Deployment and management scripts
- `doc/` - Architecture and design documentation

## Critical Conventions

### SQL (See CONVENTIONS.md for full details)

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

### TypeScript/Next.js (See app/CONVENTIONS.md for full details)

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
- Generated via `./devops/manage-statbus.sh generate-types`
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
echo "SELECT command, COUNT(*), SUM(duration_ms)::numeric(10,0) as total_ms FROM worker.tasks WHERE state = 'completed' GROUP BY command ORDER BY total_ms DESC;" | ./devops/manage-statbus.sh psql
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

- **Backend/SQL/Infrastructure**: See `CONVENTIONS.md` in project root
- **Next.js/TypeScript/Frontend**: See `app/CONVENTIONS.md`
- **Data Model**: See `doc/data-model.md`
- **Authentication**: See `doc/auth-design.md`
