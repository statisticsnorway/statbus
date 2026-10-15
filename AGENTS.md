# STATBUS agent guide

STATBUS is SSB's statistical business registry: PostgreSQL 18+, PostgREST 12+, Next.js 15+, and a Go CLI. PostgreSQL is the backend. PostgREST exposes the schema directly, with authorization enforced by database roles and RLS.

## Communication and context

- Lead with the answer or result. Include only decision-relevant rationale, verification, and blockers. Do not repeat context or narrate routine steps.
- Keep instructions actionable: one rule per bullet, with examples only where needed. Put procedures in linked guides and incident histories in tickets or Git history.
- Read the topic guides below when relevant, not all at session start.
- Use memory for preferences and historical lessons, not as the only source of mandatory project rules. Keep those in version-controlled instructions. Never store secrets in memory.

## Workflow

- For multi-step work, keep an ordered todo list with one item in progress. Include implementation, verification, commit/push, CI review, ticket evidence, and closure when applicable. Add newly discovered work to the plan.
- For defects, record the hypothesis in `tmp/journal.md`, reproduce the failure, and run a non-destructive prototype before implementing. Keep diagnostic scripts and logs in `tmp/`. Do not delete them.
- Demonstrate that regression tests detect the defect: record failure before the fix and success after it. If necessary, test against the fix's parent commit without disturbing the shared checkout.
- Run the relevant regression suite. Match verification to the claim: documentation edits need diff/link checks, SQL behavior needs database tests, and host behavior needs an observed host run.
- Test real behavior or invariants, not the absence of an arbitrary retired token. Diagnose every failure rather than dismissing it as flaky or transient.
- Fix discovered bugs immediately or schedule their fix as the next step. Fail clearly on unexpected errors. Enforce data invariants with constraints and fix races.

## Shared checkout and Git

- Agents share one checkout and index. Coordinate file ownership and preserve unrelated changes.
- Commit only your files using explicit paths: `git commit -m "prefix: description" -- path/to/file`. Check `git diff --cached --stat` and the staged diff first. Never use `git add -A` or `git add .`.
- Commit and push ordinary changes to master without waiting for idle CI or asking permission, unless the user requested a review-only diff. Inspect CI for that exact SHA afterwards. Release gates are separate.
- Read GitHub Actions `status` and `conclusion` explicitly using `gh run list --json status,conclusion`. Do not rely on `gh run watch --exit-status`.

## Backlog

- Tickets live in `.backlog/tasks/`. Read with the `backlog` CLI, Backlog MCP, or `rg`. Do not look up tickets in a browser or guess tracker URLs.
- Author ticket content through the CLI. Put the goal, work, acceptance criteria, and evidence in the ticket, not only in agent prompts.
- Set `In Progress` when work starts, including delegation. After verification, set `Done` with `backlog task edit <id> -s "Done"` and leave it on the board. Do not use `backlog task complete` for newly finished work.
- Use `--append-notes` to add evidence. `--notes` replaces existing notes. Use `--check-ac <n>` to mark verified criteria.

## Commands and configuration

- `./sb` is the Go operations CLI. `./dev.sh` handles development tasks. Do not use the retired `manage-statbus.sh`.
- Edit `.env.config`, then run `./sb config generate`. Do not edit generated `.env`. Keep `.env.credentials` secure.
- Inspect the database with `./sb psql < file.sql` or `echo "SELECT ..." | ./sb psql`.
- For offline database definitions, search `doc/db/` before chronological migrations.
- Run SQL tests with `./dev.sh test fast` or `./dev.sh test <prefix>`. Save output with `2>&1 | tee tmp/test-<name>.log` and preserve the test exit status with `set -o pipefail`.
- Frontend checks run from `app/`: `pnpm run lint`, `pnpm run format`, `pnpm run tsc`, `pnpm run test`, and `pnpm run build`.
- Database deletion/recreation commands are local-development only, never production. Confirm the target and authorization before destructive operations.
- Additional commands and connection examples: [development reference](doc/development-reference.md).

## Database changes

Before SQL work, read [SQL conventions](.claude/rules/sql.md). Before migrations, also read the [migration procedure](doc/development-reference.md#migrations).

- Dump the current function/procedure with `\sf` before editing. Use it as the base for both migration directions, then change only the required lines. Never mix stderr into the SQL dump.
- Released migrations are immutable. Repair wrong data in a forward migration, testing both migrated seed rows and rows written while the bad state existed.
- Migration data operations must be deterministic across full replay and incremental upgrades. Do not derive values from aggregates of unrelated current state such as `MAX(priority)` or `COUNT(*)`.
- Regenerate `doc/db/` with migration changes. Let `./dev.sh generate-doc-db` finish and verify it left no unintended deletions before committing.
- Preserve the authentication split: JWT verification uses `SECURITY DEFINER`, role switching uses `SECURITY INVOKER`. Protect secrets with RLS and review definer privileges and search paths.

## Frontend changes

Before editing `app/`, read [frontend conventions](.claude/rules/frontend.md).

- Prefer direct browser-to-`/rest` requests. Use `/api` only when server-side work is necessary, such as bulk COPY or webhooks.
- Keep independently changing state in separate Jotai atoms. Use `atomEffect` for set-if-null patterns and `useGuardedEffect` instead of `useEffect`. State-machine effects depend on primitives, not whole state objects.
- Match local variable names to their atoms. Use `@/` imports from `app/src/` and prefer named exports.
- Generate database types with `./sb types generate`. Use `Tables<'name'>` and `Enums<'name'>` from `app/src/lib/database.types.ts`.

## Install, upgrade, and deployment

Before touching these paths, read [install/upgrade testing](doc/install-upgrade-testing.md), the [upgrade timeline](doc/upgrade-timeline.md), and the [recovery model](doc/upgrade-recovery-model.md).

- Validate released-image behavior by committing, pushing, waiting for the per-commit image, then running it in a real guest. Local reasoning or unit tests alone do not establish install/upgrade success.
- Deploy named release candidates, never master's untagged tip. Register the version, schedule it, then let the service run or invoke `./sb install` to dispatch immediately. Check the remote working tree is clean first.
- `./sb install` is the unified first-install, repair, and pending-upgrade entrypoint. Follow its recovery contract rather than inventing manual recovery steps.
- Dev is the automatic canary. Norway is the human-operated prerelease canary and must not receive automated pushes. Demo and ordinary production slots follow the stable channel.
- Deployment mode controls Caddy behavior. Deployment slot controls instance isolation and port allocation. Do not conflate them.
- Internal database clients use `CADDY_DB_BIND_ADDRESS` and `CADDY_DB_PORT`, not the external `SITE_DOMAIN`. Keep the PostgREST admin port loopback-only, with no public Caddy route.

## Topic guides

| Task | Read |
|------|------|
| Commands, migration procedure, connections, performance | [Development reference](doc/development-reference.md) |
| SQL conventions and examples | [SQL rules](.claude/rules/sql.md) |
| Frontend conventions and examples | [Frontend rules](.claude/rules/frontend.md) |
| Complex multi-agent coordination | [Agentic methodology](doc/agentic-methodology.md) |
| Data model or authentication | [Data model](doc/data-model.md), [authentication](doc/auth-design.md) |
| Release gates and recovery tests | [Release ladder](doc/release-ladder.md), [recovery runner](test/install-recovery/README.md) |
| Cloud or standalone deployment | [Cloud](doc/CLOUD.md), [deployment](doc/DEPLOYMENT.md) |
| Imports or external integrations | [Import system](doc/import-system.md), [integration](doc/INTEGRATE.md) |
