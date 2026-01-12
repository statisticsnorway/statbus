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

**⚠️ DESTRUCTIVE Operations (LOCAL DEVELOPMENT ONLY - NEVER IN PRODUCTION):**
```bash
./devops/manage-statbus.sh create-db        # Create database with migrations
./devops/manage-statbus.sh delete-db        # ⚠️ DESTROYS ALL DATA
./devops/manage-statbus.sh delete-db-structure  # ⚠️ Drops schema, keeps container
```

### Testing
```bash
./devops/manage-statbus.sh test all              # Run all pg_regress tests
./devops/manage-statbus.sh test 015_my_test      # Run single test (prefix number)
```

### Migrations
```bash
cd cli && ./bin/statbus migrate new --description "my change"  # Create migration
cd cli && ./bin/statbus migrate up                             # Apply migrations
cd cli && ./bin/statbus migrate down                           # ⚠️ Rollback (destructive)
```

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
