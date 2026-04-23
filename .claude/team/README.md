# Team

A cost-aware specialization pattern for Claude Code. Each role names both *what an agent does* and *at what cost tier they do it*, so expensive models stay lean and delegate context-heavy work down to cheaper ones.

This folder is portable. To reuse in another project: copy `.claude/team/` and `.claude/hooks/`, then edit each role's prompt for the new project's commands.

## Roster

| Role | Model | Purpose |
|---|---|---|
| `foreman` | Opus (1M ctx) | Team-lead. Coordinates the user conversation, decomposes work, delegates, reviews, signs off. The only agent the user talks to directly. |
| `engineer` | Opus (1M ctx) | Designs and builds. Forges architectural changes. Commits its own work; passes to foreman for review. Destructive or cross-cutting commits need foreman approval first. |
| `mechanic` | Sonnet | Diagnoses and fixes. Targeted investigations, one-shot writes. No multi-step reasoning across turns — that goes back to foreman. |
| `tester` | Haiku | Runs test commands. Single assignment, no concurrent-run collisions. |
| `operator` | Haiku | Legwork: reads, greps, SSH diagnostics, log tails, small one-shot writes, deploy drive-throughs. Parses long output, summarizes, reports back with file paths and line numbers. |

## Why this shape

Three forces drive the design:

**Money.** Opus is expensive; Haiku is cheap. Routing grep and log-parsing through Haiku instead of Opus keeps burn rates low without losing the work.

**Focus.** Expensive models protect their context by delegating. When the mechanic needs to understand a 2000-line log, the operator reads it and hands back a three-line summary plus the relevant line numbers. The mechanic only looks at what matters.

**No contention.** When one named role owns a command class, two agents can't accidentally run the same destructive thing at the same time. The `tester` is the single runner for `./dev.sh test`; no coordination protocol needed.

## Cost/context hierarchy

The delegation flow runs downhill by cost:

- Foreman → engineer: design questions, architectural work.
- Engineer → mechanic: targeted diagnosis of a component.
- Engineer or mechanic → operator: "read this file and summarize the part about X, with line numbers."
- Foreman → tester: "run the tests."

The rule of thumb: if a read or command-run will produce a long output, the expensive model should delegate it to a cheaper model, who summarizes and reports back. The expensive model only sees the filtered result, protecting context for the work that actually needs judgment.

## Command ownership

Collisions disappear when only one named role owns each command. On this project:

- Tests (`./dev.sh test fast`, `./dev.sh test <name>`, `./dev.sh test <names…>`) → **tester**
- Migrations, types generation, doc generation, builds → **engineer** (delegated to operator when output is long or mechanical)
- Release commands (`./sb release prerelease`) → **foreman**

Per-project commands live in the role files (`engineer.md`, `tester.md`, etc.), not here.

## Hooks

Three hooks in `.claude/hooks/` enforce the pattern at the harness level:

- **`restrict-agent-spawn.sh`** — only foreman can spawn agents; command-class gates route shared commands to their named owner.
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
- [mechanic.md](mechanic.md) — diagnose + fix (Sonnet)
- [tester.md](tester.md) — run tests (Haiku)
- [operator.md](operator.md) — legwork + summarize (Haiku)
