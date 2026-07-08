# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.
Claude Code also auto-loads `.claude/rules/*.md` files contextually based on which files are being edited.

## Team (Claude Code team functionality)

This project uses **Claude Code's built-in team functionality** (the multi-agent Team feature). **Our team name is `statbus`** — always create and join the team under this exact name, never the generic `team`.

Why the name matters: the team name is a single global namespace (`~/.claude-veridit/teams/<name>/config.json`). A generic name like `team` collides with other concurrent Claude Code sessions on this machine — a parallel project's same-named team clobbers our roster and cross-delivers messages. A project-specific name keeps each session's team isolated. Foreman bootstrap: `TeamCreate({team_name: "statbus", ...})`.

### Task board — Backlog.md, NOT the harness Task* list

The team's task board is **Backlog.md** (the `mcp__backlog__task_*` tools). The harness `TaskCreate` is **blocked** by `.claude/hooks/require-backlog-tasks.sh` — the harness `Task*` list is volatile (it does not survive `/clear` or compaction and is not the shared source of truth). Coordinate via Backlog.md tasks (create / assign / note / close with the backlog MCP) plus `SendMessage`. Full workflow: the BACKLOG WORKFLOW section below.

### Roles (read only yours)

If you are assigned a role on this project, read `.claude/team/<your-role>.md` and nothing else from that folder. If you are the foreman, also read `.claude/team/README.md` for the full roster, delegation pattern, and cost rationale. Do not read other roles' files — each agent loads only what they need.

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

### Review Handoff = Freeze
Reporting a unit for review FREEZES it — no further edits until the verdict lands,
or the reviewer verifies a moving target and one-breaker-at-a-time silently slips.
A better idea discovered mid-wait is ANNOUNCED first ("pulling the unit back,
reason X"), then applied; the review restarts on the new state.

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

When `./sb install` routes to the scheduled-upgrade dispatch, it does **not** acquire the install-held flag. `executeUpgrade` writes its own service-held flag internally before any destructive step. Ownership of the mutex transfers cleanly across the boundary via this filesystem-level handshake. Don't wrap `svc.ExecuteUpgradeInline` with an install-flag acquire — the second `acquireFlock` would fail with `EWOULDBLOCK` (the process already holds the flock); let `executeUpgrade` write its own service-held flag.

Full reference: `doc/upgrade-timeline.md`.

## macOS dev note: restarting Docker Desktop

When Docker Desktop is unresponsive, try `open -a Docker` (macOS) and wait for health — don't stall waiting for the user. If `docker compose ps` fails with "Docker Desktop is unable to start", restart it programmatically.

## Import validation discipline

Code follows fail-fast (actionable error). Import follows **two-tier validation**:

1. **Unprincipled → fail fast.** The system cannot store the row coherently (invalid FK, contradictory cross-table link, ambiguous target). Hard error, row skipped, actionable message.
2. **Data missing but foundation sound → warning.** Row stored, soft error logged, operator improves source later.

Silent acceptance is reserved for **valid stored data** — there is no missingness to surface because the absence is part of a correct, principled state. Silent acceptance is **not** a third tier; treating "expected absence" as a deliberate non-signal is a data-corruption pathway.

When designing per-step import validation, classify every input scenario into one of these three categories. If unsure, default to warning over silence.

<!-- BACKLOG.MD MCP GUIDELINES START -->

<CRITICAL_INSTRUCTION>

## BACKLOG WORKFLOW INSTRUCTIONS

This project uses Backlog.md MCP for all task and project management activities.

**CRITICAL GUIDANCE**

- If your client supports MCP resources, read `backlog://workflow/overview` to understand when and how to use Backlog for this project.
- If your client only supports tools or the above request fails, call `backlog.get_backlog_instructions()` to load the tool-oriented overview. Use the `instruction` selector when you need `task-creation`, `task-execution`, or `task-finalization`.

- **First time working here?** Read the overview resource IMMEDIATELY to learn the workflow
- **Already familiar?** You should have the overview cached ("## Backlog.md Overview (MCP)")
- **When to read it**: BEFORE creating tasks, or when you're unsure whether to track work

These guides cover:
- Decision framework for when to create tasks
- Search-first workflow to avoid duplicates
- Links to detailed guides for task creation, execution, and finalization
- MCP tools reference

You MUST read the overview resource to understand the complete workflow. The information is NOT summarized here.

</CRITICAL_INSTRUCTION>

<!-- BACKLOG.MD MCP GUIDELINES END -->
