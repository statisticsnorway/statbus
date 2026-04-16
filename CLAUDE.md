# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.
Claude Code also auto-loads `.claude/rules/*.md` files contextually based on which files are being edited.

## Worker: Structured Concurrency (MUST READ)

The worker uses **structured concurrency** — exactly ONE top-level task at a time per queue, with parallel children within scoped parent-child relationships. Top fiber blocks until all children complete. This is NOT "fire and forget" concurrency.

See `doc/derive-pipeline.md` for the full pipeline diagram and `doc/worker-structured-concurrency.md` for the concurrency model. Based on [Trio nurseries](https://vorpus.org/blog/notes-on-structured-concurrency-or-go-statement-considered-harmful/).

## Remote SSH + psql (CRITICAL)

**NEVER `echo "SQL" | ssh host "psql"`** — quoting breaks across SSH + shell + psql layers.

Instead, write SQL to a local `tmp/` file and pipe it:
```bash
# Write SQL to a temp file
cat > tmp/query.sql << 'EOF'
SELECT id, state FROM worker.tasks LIMIT 5;
EOF

# Pipe to remote psql
ssh statbus_demo "cd statbus && cat | ./sb psql" < tmp/query.sql

# Or for local psql
./sb psql < tmp/query.sql
```

This avoids quoting hell and creates a log of what was run.

## Background Tasks (CRITICAL)

**Never block the conversation waiting for background tasks.** Claude Code auto-notifies when they complete.

- Use `| tee tmp/logfile.log` to capture output from long commands
- Use `run_in_background: true` for tests, builds, and other slow commands
- **Continue working and talking** while background tasks run — never sleep, poll, or issue blocking `TaskOutput` calls
- You will receive a `<task-notification>` automatically when a background task finishes

## Parallel Agents

All agents work on the **same working tree** (no worktrees — shared database prevents parallel Docker Compose).

### Master Is the Stable Build
Master must always build and pass tests. If master breaks, revert immediately.

### Single Tree, Disjoint Files
- **Split by file ownership.** Never two agents editing the same file.
- **One breaker at a time.** Only one agent in a "code is broken, fixing it" state.
- Coordinator assigns file ownership before launching parallel agents.

### Coordinator Role
Main conversation is the COORDINATOR. Agents do research and propose edits. Coordinator reviews and commits.

1. Agent finishes work, reports results
2. Coordinator inspects — read scratchpad, check changes
3. Coordinator commits (agents don't commit directly)
4. Verify build + tests pass after commit

### Agent Scratchpads
Every agent gets `tmp/agents/<agent-name>.md`. Writes progress, findings, decisions, next steps. If killed, read the scratchpad and continue. Not committed — working notes.

### Agent Tooling Protocol
Agents that debug issues should BUILD DIAGNOSTIC TOOLS, not just debug. Add trace flags, logging, or diagnostic endpoints as permanent infrastructure. Every time an agent wishes it could see something, it should ADD the tool to see it.

@AGENTS.md

## Install / Upgrade: the unified `./sb install` entrypoint

`./sb install` is the single operator-facing entrypoint that covers first-install, repair, and dispatching a pending upgrade. It runs an 8-state probe ladder (`cli/internal/install/state.go`) and selects an action:

1. **fresh** — no `.env.config` → step-table
2. **live-upgrade** — flag present, holder PID alive → refuse
3. **crashed-upgrade** — flag present, holder PID dead → `RecoverFromFlag`, re-detect, re-dispatch
4. **half-configured** — config present, `.env.credentials` missing → step-table
5. **db-unreachable** — creds present, DB down → step-table (will start it)
6. **legacy-no-upgrade-table** — DB up, no `public.upgrade` → refuse (pre-1.0; manual upgrade)
7. **scheduled-upgrade** — pending row in `public.upgrade` → dispatch through `executeUpgrade` inline
8. **nothing-scheduled** — everything healthy → step-table as an idempotent config refresh

**Flag-file ownership contract.** The mutex primitive is `tmp/upgrade-in-progress.json`. Two distinct holders:
- `Holder="install"` — written by `acquireOrBypass` when install runs the step-table. Released by `defer ReleaseInstallFlag` on any exit.
- `Holder="service"` — written by `writeUpgradeFlag` inside `executeUpgrade`, regardless of who invoked it.

When `./sb install` routes to the scheduled-upgrade dispatch, it does **not** acquire the install-held flag. `executeUpgrade` writes its own service-held flag internally before any destructive step. Ownership of the mutex transfers cleanly across the boundary via this filesystem-level handshake. Don't wrap `svc.ExecuteUpgradeInline` with an install-flag acquire — you'll self-deadlock on the second writer's `O_EXCL`.

Full reference: `doc/upgrade-system.md` and `doc/install-mutex.md`.

## macOS dev note: restarting Docker Desktop

When Docker Desktop is unresponsive, try `open -a Docker` (macOS) and wait for health — don't stall waiting for the user. If `docker compose ps` fails with "Docker Desktop is unable to start", restart it programmatically.
