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

@AGENTS.md
