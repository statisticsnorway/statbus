# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.
Claude Code also auto-loads `.claude/rules/*.md` files contextually based on which files are being edited.

## Worker: Structured Concurrency (MUST READ)

The worker uses **structured concurrency** — exactly ONE top-level task at a time per queue, with parallel children within scoped parent-child relationships. Top fiber blocks until all children complete. This is NOT "fire and forget" concurrency.

See `doc/derive-pipeline.md` for the full pipeline diagram and `doc/worker-structured-concurrency.md` for the concurrency model. Based on [Trio nurseries](https://vorpus.org/blog/notes-on-structured-concurrency-or-go-statement-considered-harmful/).

@AGENTS.md
