# Team

A cost-aware specialization pattern for Claude Code. Each role names both *what an agent does* and *at what cost tier they do it*, so expensive models stay lean and delegate context-heavy work down to cheaper ones.

This folder is portable. To reuse in another project: copy `.claude/team/` and `.claude/hooks/`, then edit each role's prompt for the new project's commands.

## Roster

| Role | Model | Effort | Purpose |
|---|---|---|---|
| `foreman` | Opus (1M ctx) | high | Team-lead. Coordinates the user conversation, decomposes work, delegates, reviews, signs off. The only agent the user talks to directly. |
| `engineer` | Opus (1M ctx) | extra-high | Designs and builds. Forges architectural changes. Commits its own work; passes to foreman for review. Destructive or cross-cutting commits need foreman approval first. |
| `architect` | Opus (1M ctx) | max | Future planning: system shape, architectural decisions, problem framings. Produces plans as **backlog documents** (via the backlog MCP), not code; hands approved plans to engineer for execution. |
| `mechanic` | Sonnet | default | Diagnoses and fixes. Targeted investigations, one-shot writes. No multi-step reasoning across turns — that goes back to foreman. |
| `tester` | Haiku | default | Runs test commands. Single assignment, no concurrent-run collisions. |
| `operator` | Haiku | default | Legwork: reads, greps, SSH diagnostics, log tails, small one-shot writes, deploy drive-throughs. Parses long output, summarizes, reports back with file paths and line numbers. |

The **Effort** column is the second axis (alongside Model): the Opus agents run at distinct effort tiers — foreman `high` (coordination), engineer `extra-high` (build precision), architect `max` (deepest design judgment). Effort, like model, costs money + time.

## Why this shape

Three forces drive the design:

**Money.** Opus is expensive; Haiku is cheap. Routing grep and log-parsing through Haiku instead of Opus keeps burn rates low without losing the work.

**Focus.** Expensive models protect their context by delegating. When the mechanic needs to understand a 2000-line log, the operator reads it and hands back a three-line summary plus the relevant line numbers. The mechanic only looks at what matters.

**No contention.** When one named role owns a command class, two agents can't accidentally run the same destructive thing at the same time. Routing tests to the `tester` is the coordination convention. Test-run *serialization* is no longer enforced by role identity, though: `./dev.sh` takes an exclusive lock itself (`acquire_test_run_lock`), so any second run that would touch the shared pg_regress state fails loudly instead of corrupting it — the guard holds even after a `/clear` or crash leaves the roster ambiguous.

## Cost/context hierarchy

The delegation flow runs downhill by cost:

- Foreman → engineer: design questions, architectural work.
- Foreman → architect: future planning — what to build next and how to shape it before it lands on the team.
- Engineer → mechanic: targeted diagnosis of a component.
- Engineer or mechanic → operator: "read this file and summarize the part about X, with line numbers."
- Foreman → tester: "run the tests."

Architect and engineer sit on the same cost tier (both Opus) but split by horizon: architect plans what's *next*, engineer builds what's *now*. An architect plan, once ratified, becomes engineer's brief.

The rule of thumb: if a read or command-run will produce a long output, the expensive model should delegate it to a cheaper model, who summarizes and reports back. The expensive model only sees the filtered result, protecting context for the work that actually needs judgment.

### Effort escalation — lowest tier first, bump only on failure

The model+effort ladder, low → high: **operator / tester (Haiku) → mechanic (Sonnet) → engineer (Opus, extra-high) → architect (Opus, max)** (foreman runs Opus at `high` and coordinates).

Route each task to the **lowest tier that can plausibly do it**, and escalate to a higher-effort agent **only when the lower one demonstrably fails** — wrong result, can't complete, or the task needs judgment above its rung. Don't pre-escalate on a guess; try low first, and when you bump a task up a rung, record why. The principle: **effort is money + time — we don't spend it unless the task needs it.** A grep doesn't go to the architect; a one-shot fix goes to the mechanic before the engineer; only genuine architecture reaches the engineer, only system-shaping design reaches the architect.

## Command ownership

Collisions disappear when only one named role owns each command. On this project:

- Tests (`./dev.sh test fast`, `./dev.sh test <name>`, `./dev.sh test <names…>`) → **tester**
- Migrations, types generation, doc generation, builds → **engineer** (delegated to operator when output is long or mechanical)
- Release commands (`./sb release prerelease`) → **foreman**

Per-project commands live in the role files (`engineer.md`, `tester.md`, etc.), not here.

## Hooks

Three hooks in `.claude/hooks/` enforce the pattern at the harness level:

- **`restrict-agent-spawn.sh`** — only foreman can spawn agents; git-history ops (commit/push/rebase/…) are blocked for operator+tester, and `./sb release prerelease` is foreman-only. (It no longer gates `./dev.sh test` — that serialization moved to the `acquire_test_run_lock` flock in `dev.sh`.)
- **`route-alias.sh`** — catches typo'd recipient names in SendMessage and Task owner fields (turns the silent-drop bug into a loud error).
- **`require-task-slug.sh`** — every task subject must start with a `slug-name: description` prefix so the user has a conversational handle without seeing the UI.

The hooks are what make the team behave; without them, agents drift back to generic spawns and the cost structure dissolves.

## Bootstrap

Each role has a spawn prompt in this folder. A new session:

1. `TeamCreate({team_name: "team", description: "..."})`
2. For each role file, spawn a background agent with `mode: "bypassPermissions"`, passing the file body as the prompt. The frontmatter names the model.
3. Each role replies "Ready." and waits for work.

The foreman (you, the team-lead) orchestrates from there.

## Role files

- [foreman.md](foreman.md) — the coordinator role (this is you, the session itself)
- [engineer.md](engineer.md) — design + build (Opus)
- [architect.md](architect.md) — future planning + design (Opus)
- [mechanic.md](mechanic.md) — diagnose + fix (Sonnet)
- [tester.md](tester.md) — run tests (Haiku)
- [operator.md](operator.md) — legwork + summarize (Haiku)
