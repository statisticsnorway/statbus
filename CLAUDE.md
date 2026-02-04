# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

STATBUS is a statistical business registry with temporal tables for tracking business activity throughout history. Built by Statistics Norway (SSB) using PostgreSQL 18+, PostgREST 12+, and Next.js 15+.

**Architecture**: Database-centric progressive disclosure (NOT microservices). PostgreSQL IS the backend—PostgREST exposes the schema directly. Security happens entirely at the database layer via Row Level Security (RLS).

## Essential Commands

### Database Operations
```bash
./devops/manage-statbus.sh start all              # Start all services
./devops/manage-statbus.sh psql                   # Open psql shell
./devops/manage-statbus.sh psql < file.sql        # Run SQL file (< redirection required!)
echo "SELECT ..." | ./devops/manage-statbus.sh psql  # Single query
./devops/manage-statbus.sh generate-types         # Generate TypeScript types from schema
./devops/manage-statbus.sh create-db              # Create database with migrations
./devops/manage-statbus.sh recreate-database      # Delete + Create (fresh start)
```

### Database Inspection
```bash
echo "\d tablename" | ./devops/manage-statbus.sh psql    # Table structure
echo "\sf schema.function_name" | ./devops/manage-statbus.sh psql  # Function definition
echo "\dt pattern*" | ./devops/manage-statbus.sh psql    # Find tables by pattern
```

### Testing
```bash
./devops/manage-statbus.sh test fast 2>&1 | tee tmp/test-fast.log  # Fast tests (use tee!)
./devops/manage-statbus.sh test 015_my_test                        # Single test
./devops/manage-statbus.sh diff-fail-all pipe                      # Show diffs for failed tests
```

### Migrations
```bash
cd cli && ./bin/statbus migrate new --description "my change"  # Create migration
cd cli && ./bin/statbus migrate up                             # Apply migrations
cd cli && ./bin/statbus migrate down                           # Rollback migration
```

**When modifying existing functions**: Always dump current definition first with `\sf`, then modify:
```bash
echo "\sf schema.function_name" | ./devops/manage-statbus.sh psql > tmp/function_def.sql
```

### Next.js (from app/ directory)
```bash
cd app && pnpm run dev          # Dev server with Turbopack
cd app && pnpm run build        # Production build
cd app && pnpm run lint         # ESLint
cd app && pnpm run tsc          # Type check
cd app && pnpm run test         # Jest tests
```

## Key Conventions

### SQL
- Dollar-quote function bodies with function name: `AS $my_function$`
- Use `format($$...$$)` for dynamic SQL (avoids quote escaping)
- Temporal logic in chronological order: `start <= point AND point < end`
- Table aliases with explicit AS: `FROM my_table AS mt`
- Naming: `x_id` (FK), `x_ident` (external id), `x_at` (TIMESTAMPTZ), `x_on` (DATE)
- Temp table cleanup: `IF to_regclass('pg_temp.my_table') IS NOT NULL THEN DROP TABLE my_table; END IF;`

### TypeScript/React
- **CRITICAL**: Small, independent Jotai atoms prevent re-render loops. If state changes independently, it MUST be its own atom.
- ALL effects MUST use `useGuardedEffect` instead of `useEffect`
- Format: `useGuardedEffect(callback, deps, 'FileName.tsx:purpose')`
- Prefer direct `/rest` requests over `/api` routes (transparency, debugging, user learning)
- Generated DB types: `Tables<'my_table'>`, `Enums<'my_enum'>`

## Development Workflow

Follow this cycle for all changes, especially bug fixes:

1. **Hypothesize**: State hypothesis in `tmp/journal.md`
2. **Isolate**: Create/identify reproducing test
3. **Prototype**: Non-destructive verification in `tmp/verify_fix.sql`
4. **Observe**: Run prototype, gather evidence (MANDATORY)
5. **Analyze**: If successful → proceed. If not → return to step 1
6. **Implement**: Propose permanent changes only after prototype succeeds
7. **Validate**: Run test suite

**Never skip the prototype step.**

## Project Structure

- `migrations/` - Database migrations (YYYYMMDDHHmmSS_description.up/down.sql)
- `app/` - Next.js 15 application (App Router, TypeScript, Tailwind, shadcn/ui)
- `cli/` - Crystal CLI tool for migrations and database management
- `test/sql/` - pg_regress SQL tests; expected output in `test/expected/`
- `devops/` - Deployment and management scripts
- `doc/` - Architecture and design documentation
- `tmp/` - Diagnostic SQL, journals, debug scripts (gitignored, don't delete)

## Full Documentation

- **Backend/SQL**: See `CONVENTIONS.md` in project root
- **Frontend/TypeScript**: See `app/CONVENTIONS.md`
- **AI Agent Quick Reference**: See `AGENTS.md`
- **Data Model**: See `doc/data-model.md`
