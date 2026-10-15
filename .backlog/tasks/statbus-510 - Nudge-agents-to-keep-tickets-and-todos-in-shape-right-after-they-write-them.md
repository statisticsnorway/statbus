---
id: STATBUS-510
title: 'Nudge agents to keep tickets and todos in shape, right after they write them'
status: Done
assignee: []
created_date: '2026-10-15 16:15'
updated_date: '2026-10-15 16:31'
labels: []
dependencies: []
priority: medium
ordinal: 436204
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
### North Star
AI agents working in STATBUS write tickets that meet the house standard, and keep their todos and tickets in step, because they get corrected the moment they write, not later.

### Zoom out
Feedback that arrives later (CI, review) does not change what the agent does next, so mistakes pile up in the backlog. A nudge in the result of the very tool call that wrote the ticket does change it: the agent reads it and fixes the ticket. It is a nudge, not a gate.

### Zoom in
A local Jcode post_tool_feedback hook, configured in the STATBUS Jcode instance (/Users/jhf/ssb/.jcode/config.toml) and acting only inside this repository:
- After a ticket create/edit: an independent DeepSeek Flash reviewer (no tools) returns up to three specific corrections; the agent fixes them and the next save is reviewed again, within a small bound.
- After a ticket is created: remind the agent to plan the work in its todos, including delegation, collecting worker results, verification and ticket updates.
- When todos are written: remind the agent to keep the related ticket up to date at the right steps.
No CI. Nothing outside this repository is affected.

### Closing review
Before Done, decide whether memory, docs (AGENTS.md) or cleanup are needed; record none needed where appropriate.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 A real ticket create/edit in this repo returns specific corrections in the same tool result; the agent can act on them and the next save is reviewed again.
- [x] #2 After ticket creation the feedback asks for a todo plan covering delegation, reaping, verification and ticket updates.
- [x] #3 Writing todos returns a short reminder to keep the related ticket in sync.
- [x] #4 Reads, unchanged saves and work outside this repository get no feedback; reviewer failures say so plainly and never claim approval.
- [x] #5 Installed in the STATBUS instance by a repeatable script (ops/jcode/install.py) and observed firing in a real session.
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
### Evidence (2026-10-15, before enabling)
Hook: ops/jcode/ticket_feedback.py (post_tool_feedback, DeepSeek Flash, no CI). Live runs: real Jcode, real Backlog MCP, sandbox repo /Users/jhf/ssb/.jcode/scratch/ticket-feedback-510, runner tmp/510-live.py.
- Without hook (tmp/510-live-without.log): 0 feedback blocks; the ticket used Problem/Goal/Scope, with no North Star, Zoom out/in or closing review.
- With hook, run 1 (tmp/510-live-with-run1.log): agent got corrections, the todo-plan reminder and the todo sync nudge, and acted on them. Defects found: the review-limit message repeated 4 times, and the rubric pushed scope growth (5 ACs, 5 DoD items, sections moved into notes).
- Fix: limit message shown once, rubric told to prefer cutting to adding and to accept honest evidence-to-be-found. Run 2 (tmp/510-live-with.log): final ticket in house format, 3 ACs, no repeats.
- Run 2 had one "unavailable" review. Re-running the reviewer on that ticket 3 times gave valid replies, so the failure was not reproduced; unavailable messages now carry the reason.
- Direct checks on this repo: reads, other repos under /Users/jhf/ssb, non-ticket edits, pre_tool and unchanged saves are silent; a real edit of STATBUS-510 is reviewed; first todo write nudges, a repeat does not.
Known limits: the reviewer varies run to run (same ticket gave different findings); a nudge, not a gate.

### Installed (owner approved, 2026-10-15)
- `python3 ops/jcode/install.py` adds the hook to the STATBUS instance config (/Users/jhf/ssb/.jcode/config.toml), keeping existing hooks and a timestamped backup; `--uninstall` removes it. A repeat run changes nothing. Checked on copies of this instance, the home instance (other hooks kept), a config with an existing feedback hook, and one with no [hooks] section: install, repeat and uninstall all round-trip.
- Home instance config hash unchanged after the install.
- Real new session using only the installed config (tmp/510-installed-check.log): a task_edit of this ticket returned a review in the same tool result. Its two findings were correct (stale "only after owner approval" in AC5; a vague notes line) and were fixed in this edit.

### Closing review (2026-10-15)
- **Docs:** none needed beyond the script docstrings; ops/jcode/install.py --help documents install and uninstall.
- **Memory:** none needed; the hook itself carries the rule into every session.
- **Cleanup:** the sandbox under /Users/jhf/ssb/.jcode/scratch and the tmp/ logs stay as diagnostics (tmp/ is never deleted). Nothing else left behind.
<!-- SECTION:NOTES:END -->
