# STATBUS agent guide

STATBUS is SSB's statistical business registry: PostgreSQL 18+, PostgREST 12+, Next.js 15+, and a Go CLI. PostgreSQL is the backend. PostgREST exposes the schema directly, with authorization enforced by database roles and RLS.

## Communication and context

- Lead with the answer or result. Include only decision-relevant rationale, verification, and blockers. Do not repeat context or narrate routine steps.
- Keep instructions actionable: one rule per bullet, with examples only where needed. Put procedures in linked guides and incident histories in tickets or Git history.
- Document meaning at its definition: a column, type or function states what it is for, and why, in its own comment (`COMMENT ON` for schema objects). A reader who finds the definition then understands the use without a separate rule. Comments at use sites point to that definition and describe the positive design, never a bare "never X".
- Read the topic guides below when relevant, not all at session start.
- Use memory for preferences and historical lessons, not as the only source of mandatory project rules. Keep those in version-controlled instructions. Never store secrets in memory.

## Workflow

- Todos are the agent's execution plan, not the ticket tracker. Order the full workflow: implement, test, commit/merge, push, inspect CI, record ticket evidence, then close the ticket. Keep one step in progress, update it as work happens, and continue to the next step. Include ticket updates where they belong in that sequence.
- For defects, record the hypothesis in `tmp/journal.md`, reproduce the failure, and run a non-destructive prototype before implementing. Keep diagnostic scripts and logs in `tmp/`. Do not delete them.
- Demonstrate that regression tests detect the defect: record failure before the fix and success after it. If necessary, test against the fix's parent commit without disturbing the shared checkout.
- Run the relevant regression suite. Match verification to the claim: documentation edits need diff/link checks, SQL behavior needs database tests, and host behavior needs an observed host run.
- A test asserts the state or behavior the system must reach: the rows, transitions and outputs it is defined to produce. A check that some known bad thing is absent, or that a string appears in text, is a claim to predict the future: the next defect takes another form and passes it, while the check adds bloat. Delete such checks when a positive assertion covers the behavior. Diagnose every failure rather than dismissing it as flaky or transient.
- Fix discovered bugs immediately or schedule their fix as the next step. Fail clearly on unexpected errors. Enforce data invariants with constraints and fix races.

## Shared checkout and Git

- Agents share one checkout and index. Coordinate file ownership and preserve unrelated changes.
- Commit only your files using explicit paths: `git commit -m "prefix: description" -- path/to/file`. Check `git diff --cached --stat` and the staged diff first. Never use `git add -A` or `git add .`.
- Commit and push ordinary changes to master without waiting for idle CI or asking permission, unless the user requested a review-only diff. Inspect CI for that exact SHA afterwards. Release gates are separate.
- Read GitHub Actions `status` and `conclusion` explicitly using `gh run list --json status,conclusion`. Do not rely on `gh run watch --exit-status`.

## Tasks: hug
Track all work with hug tasks (on the git branch "hug/tasks", at .hug/tasks/).
Start: hug task next, then hug task take ID --model MODEL (the model you are, e.g.
claude-opus-5-5 or gpt-6.1-sol; a person: --model human; --as NAME adds your agent
or session name, optional), then hug task show ID.
While working: hug task check ID N "evidence" ticks check N and notes what shows it
holds; hug task note ID "text" for anything else.
Two tasks that ship together (one change or release): take the second with the
first, hug task take B --with A --model MODEL; both are doing.
Finish: hug task done ID when every acceptance check is ticked. Done asks whether
the instructions guided you well; answer honestly with --reflect "...": quote the
instruction that misled you or left a gap and say what happened, or "nothing".
Todos are your own next steps on the task you took, nothing else: details,
evidence, waits and dependencies go in tasks (hug task note, hug task dep), never
in todos, and another agent's work is never your todo. When your todos run out,
finish the task and run hug task next: an empty todo list means take the next
task, not blocked.
New work: hug task new "short title" --goal "..." --purpose "..." --principle "..." --details "..." --accept "observable check".
Describe a task with Goal (where we aim), Purpose (why), Principle (what we do
and do not do), Relevant details, then Acceptance. Titles stay under 80
characters; detail goes in the Goal.
Epics: hug task set ID --parent EPIC; hug task promote ID N turns item N into
its own task. hug task ls --epic EPIC shows an epic and its children.
MCP tools (hug mcp): task_list, task_show, task_new, task_next, task_take (model
and cwd required: your working folder, its branch is recorded; agent optional),
task_done, task_update (actions set, check, promote, note, move, dep, drop,
request, resolve), task_requests.
Requests: a person's request on a task (hug task requests) comes first in hug
task next. Turn it into changes to the ticket, then hug task resolve ID N
"what changed"; if it is unclear, hug task ask instead.
Questions: one question per ask (hug task ask ID --to NAME "..."), never a
numbered list in one; each is numbered on the task and the person answers each
on its own (hug task answer ID N "..."). A todo task is asked without taking it.
Requests and answers reach the board coordinator (hug task coordinator NAME) by hug itself: when a person writes hug task request or hug task answer (or r and a in hug tui), or ticks the check a question to them is about (that tick is their answer), hug hands it at once to the coordinator's live session (an idle session starts a turn, a busy one gets it at its next step) and History says delivered or not delivered with the reason. The coordinator's session acknowledges it on receipt (hug's hook), its first write on the task marks it in progress, and hug task resolve ID N answers a request (an answer: the asker's next write, its outcome, which hug hands to the coordinator the same way in one line: "NAME acted on PERSON's answer on ID: WRITE"). hug task requests shows each state: pending, acknowledged, in progress, answered. Not delivered (no coordinator set, no live session, a harness hug cannot reach yet such as Claude Code or Codex) stays "pending, not delivered: REASON" and the request still comes first in hug task next. What no live session could take goes to the coordinator's next session when it starts, once (hug's hook); a coordinator renamed before then gets it under the old name. No agent polls.
Old backlog ids (TASK-123) work as aliases.
Never edit .hug/tasks/ files by hand while another agent may be writing; use the commands.

## Commands and configuration

- The old Backlog.md board was imported into hug on 2026-11-16 and removed from the tree; its board documents are in `doc/backlog-docs/`.
- `./sb` is the Go operations CLI. `./dev.sh` handles development tasks. Do not use the retired `manage-statbus.sh`.
- Edit `.env.config`, then run `./sb config generate`. Do not edit generated `.env`. Keep `.env.credentials` secure.
- Inspect the database with `./sb psql < file.sql` or `echo "SELECT ..." | ./sb psql`.
- For offline database definitions, search `doc/db/` before chronological migrations.
- Run SQL tests with `./dev.sh test fast` or `./dev.sh test <prefix>`. Save output with `2>&1 | tee tmp/test-<name>.log` and preserve the test exit status with `set -o pipefail`.
- Frontend checks run from `app/`: `pnpm run lint`, `pnpm run format`, `pnpm run tsc`, `pnpm run test`, and `pnpm run build`.
- Node is selected with fnm from `app/.nvmrc`, and pnpm comes from Corepack at the version in `app/package.json`. An agent's non-interactive shell does not load the developer's zsh, so start app commands with `eval "$(fnm env)" && cd app && fnm use` rather than another version manager or the system Node.
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
| Data model or authentication | [Data model](doc/data-model.md), [primary units](doc/primary-units.md), [authentication](doc/auth-design.md) |
| Release gates and recovery tests | [Release ladder](doc/release-ladder.md), [recovery runner](test/install-recovery/README.md) |
| Cloud or standalone deployment | [Cloud](doc/CLOUD.md), [deployment](doc/DEPLOYMENT.md) |
| Imports or external integrations | [Import system](doc/import-system.md), [integration](doc/INTEGRATE.md) |
