# Design documents

Durable, committed design docs. They live **in git** because git is the only
store outside Claude Code's session lifecycle — anything kept only in a chat
session, or in `$CLAUDE_CONFIG_DIR/plans/` (outside the repo, config-local), is
lost when Claude Code reaps the old session.

Convention: one file per design, `kebab-case.md`. Mark each section's epistemic
status where it matters — **VERIFIED** (recovered from a durable source / live
config), **RECONSTRUCTED** (rebuilt from precedent + current code), **CONFIRM**
(needs the author's memory to validate).
