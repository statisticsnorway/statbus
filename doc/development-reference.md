# Development reference

Task-specific commands and procedures. Start with [AGENTS.md](../AGENTS.md) and read only the sections needed for the current task.

## Project map

| Path | Purpose |
|------|---------|
| `migrations/` | Timestamped up/down SQL migrations |
| `doc/db/` | Current database function, table, and view definitions |
| `test/sql/`, `test/expected/`, `test/results/` | pg_regress tests, expectations, and results |
| `app/` | Next.js application |
| `cli/` | Go CLI source, built as the gitignored `./sb` binary |
| `cli/internal/config/config.go` | Configuration generation and port calculation |
| `caddy/templates/` | Mode-specific Caddy templates |
| `ops/` | Maintenance scripts and service definitions |
| `tmp/` | Gitignored diagnostics and logs, retained for investigation |

## Operations

```bash
./sb start all                       # Profiles: all, all_except_app, app
./sb stop all
./sb restart all
./sb ps
./sb logs [service...]
./sb build [profile]                 # Development image builds
./sb config generate                 # Generate from .env.config
./sb config show
./sb config show --postgres           # Shell-evaluable PG variables
./sb users create                    # From .users.yml
./sb types generate
./sb db status
./sb db dump                         # Save under dbdumps/
./sb db download <code>
./sb db dumps list
```

Read dotenv values with `./sb dotenv -f <file> get KEY`. For deployment changes, edit `.env.config` and regenerate `.env` rather than editing the generated file. `set KEY VALUE` writes a value, and `set KEY +DEFAULT` writes only when absent.

The following can remove or overwrite data. Confirm the target and authorization first:

```bash
./sb db dumps purge [N]              # Keep newest N dumps per source
./sb db restore <file>
./sb db restore <file> --to <slot>    # Remote restore
./sb migrate down                    # Migration rollback
```

Local development only, never production: `./dev.sh create-db`, `./dev.sh delete-db`, `./dev.sh delete-db-structure`, and `./dev.sh recreate-database`. The delete/recreate commands destroy data or schema.

## Database inspection and tests

```bash
./sb psql < tmp/query.sql
echo '\d tablename' | ./sb psql
echo '\dt pattern*' | ./sb psql
echo '\dv viewname' | ./sb psql

set -o pipefail
./dev.sh test fast 2>&1 | tee tmp/test-fast.log
./dev.sh test 015_my_test 2>&1 | tee tmp/test-015_my_test.log
./dev.sh diff-fail-all pipe
./dev.sh test all 2>&1 | tee tmp/test-all.log  # Slow full suite
```

Compare `test/results/*.out` with `test/expected/*.out`. Do not rerun slow tests just to recover uncaptured output. Avoid concurrent test runs sharing database resources.

See [SQL conventions](../.claude/rules/sql.md) for naming, temporal predicates, dollar quoting, temporary tables, and transparent error tests. Match typed result variables to their types, such as `_jwt_verify_result auth.jwt_verify_result`, and give related functions common prefixes such as `jwt_verify`, `jwt_switch_role`, and `jwt_secret`.

## Migrations

```bash
./sb migrate new --description "my change"
./sb migrate up
```

When changing an existing function or procedure:

1. Rebuild a stale `./sb` before dumping. Capture the current definition without stderr:
   ```bash
   echo '\sf schema.function_name' | ./sb psql > tmp/function_def.sql
   echo '\sf schema.procedure_name' | ./sb psql > tmp/procedure_def.sql
   ```
2. Use the dump for both up and down migrations, with `CREATE OR REPLACE` and transaction wrappers. Keep the down migration as the original definition.
3. Stage only these migration paths, then make the required changes in the up migration. Review the unstaged diff for unintended changes.
4. Run the reproducing test and relevant regressions.
5. Run `./dev.sh generate-doc-db` to completion. It clears the output directories before rewriting them. Verify `git status --porcelain -- doc/db | rg '^ D'` prints nothing. Include regenerated docs with the migration commit.

Do not rewrite large routines from memory or use an old migration as the current definition. Adding `2>&1` to a definition dump can write CLI warnings into SQL.

For a released migration that wrote incorrect data, add a forward repair and test it in pg_regress:

1. Apply the faulty migration.
2. Insert/update rows that exercise the faulty state.
3. Apply the repair.
4. Assert correctness for both migrated seed rows and application-written rows.

Changing a migration hash with `IntentionallyFixBrokenImmutableMigrationEnvVar` does not repair applied data. Migration data operations must produce the same result during full replay and incremental upgrades: use fixed values, source definitions, or inputs created by the migration, not aggregates of unrelated current state.

## Frontend commands

Run from `app/`:

```bash
pnpm run dev           # Local development with Turbopack
pnpm run build
pnpm run lint          # Includes no-explicit-any gate
pnpm run format        # Prettier check
pnpm run format:fix
pnpm run tsc           # No emit
pnpm run test          # Jest
```

See [frontend conventions](../.claude/rules/frontend.md) for Jotai, request architecture, generated types, and guarded effects. An action that refreshes an async atom must await its settled state before dependent navigation: `set(authStatusCoreAtom); await get(authStatusCoreAtom);`.

## Deployment modes, slots, and connections

`CADDY_DEPLOYMENT_MODE` selects Caddy behavior:

| Mode | Behavior |
|------|----------|
| `development` | Local HTTP, internal CA for TLS testing, host Next.js on port 3000 |
| `standalone` | Public HTTPS with automatic certificates, containerized services, standard ports |
| `private` | Host proxy terminates HTTPS, slot uses HTTP and trusts forwarded headers, database accessed through SSH |

`DEPLOYMENT_SLOT_CODE` and `DEPLOYMENT_SLOT_PORT_OFFSET` isolate instances. Port base is `3000 + offset * 10`:

| Service | Base + | Local slot (offset 1) |
|---------|--------|----------------------|
| HTTP | 0 | 3010 |
| HTTPS | 1 | 3011 |
| App | 2 | 3012 |
| REST | 3 | 3013 |
| Database plaintext | 4 | 3014 |
| Database TLS/SNI | 5 | 3015 |
| REST admin | 6 | 3016 |

REST admin serves the internal `/ready` health signal. Bind it to loopback using `REST_ADMIN_BIND_ADDRESS`, with no public Caddy route. Port 3010 tests a containerized build, not the host development server at `http://local.statbus.org:3000`.

Slot codes identify containers (`statbus-<code>-app`), databases (`statbus_<code>`), cookies (`statbus-<code>`, `statbus-<code>-refresh`), and subdomains (`<code>.statbus.org`). Internal database clients use `CADDY_DB_BIND_ADDRESS` and `CADDY_DB_PORT`, not `SITE_DOMAIN`.

```bash
# Local plaintext: ./sb psql always selects this connection.
./sb psql -c 'SELECT version();'

# Local TLS/SNI testing via direct psql.
eval "$(TLS=1 ./sb config show --postgres)"
psql -c 'SELECT version();'

# Multi-tenant slot: execute SQL over SSH without exposing the database port.
ssh statbus_<slot> 'cd statbus && ./sb psql' < tmp/query.sql

# SSB standalone host.
ssh statbus@rune.statbus.org 'cd statbus && ./sb psql' < tmp/query.sql
```

For direct standalone PostgreSQL access, use the public hostname, port 5432, `PGSSLMODE=require`, `PGSSLNEGOTIATION=direct`, and `PGSSLSNI=1`. See [cloud deployment](CLOUD.md) and [standalone deployment](DEPLOYMENT.md) for server access and setup.

## Install and upgrade commands

```bash
./sb upgrade check                   # Discover candidates
./sb upgrade list
./sb upgrade register <version>
./sb upgrade schedule <version>      # Requires registration
./sb install                         # Dispatch now, or let the service run
./sb upgrade service                 # Usually managed by systemd
```

`./sb install` probes installation state and selects first-install, config refresh, repair, recovery, or pending-upgrade execution. For live/crashed upgrades, parked rows, restore reattempts, legacy refusal, and post-upgrade service restart, follow the [upgrade timeline](upgrade-timeline.md) and [recovery model](upgrade-recovery-model.md).

Read [install/upgrade testing](install-upgrade-testing.md) before changing these paths. Run `./dev.sh test-install-recovery [selector]` using the [recovery runner guide](../test/install-recovery/README.md), which documents the shared LXD fleet, credentials, smoke checkpoints, upgrade arcs, and concurrency limits. Release acceptance follows the [release ladder](release-ladder.md).

## Performance investigation

1. Enable DEBUG in `.env.config` and regenerate configuration to obtain auto_explain logs for queries over 100 ms.
2. Preserve test databases with `PERSIST=true`. Prepare local hot-patches before starting long-running tests.
3. Inspect query plans for high filter/join rejection counts, large nested loops, and sequential scans.
4. In the local test database, hot-patch the current definition with `CREATE OR REPLACE FUNCTION` and measure before creating the migration.
5. Use the [SQL optimization guidance](../.claude/rules/sql.md) to evaluate batch joins, NULL-safe comparisons, and indexes. Verify semantics as well as performance.

```bash
# Slow statements and high rejection counts.
docker compose logs db 2>&1 | rg 'duration: [0-9]{5,}' | head -30
docker compose logs db 2>&1 | rg 'Rows Removed by (Join )?Filter:' | sort | uniq -c | sort -rn | head -20

# Completed worker timings.
echo "SELECT command, COUNT(*), SUM(duration_ms)::numeric(10,0) AS total_ms FROM worker.tasks WHERE state = 'completed' GROUP BY command ORDER BY total_ms DESC;" | ./sb psql
```
