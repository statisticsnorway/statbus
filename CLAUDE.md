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
ssh statbus_demo "cd statbus && cat | ./devops/manage-statbus.sh psql" < tmp/query.sql

# Or for local psql
./devops/manage-statbus.sh psql < tmp/query.sql
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
