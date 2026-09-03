---
id: STATBUS-347
title: >-
  upgrade-log-beautification: reshape the progress log to the King-approved
  target — resolved promises, artifact lines, symmetric teardown
status: In Progress
assignee:
  - '@researcher'
created_date: '2026-09-03 08:42'
labels:
  - upgrade
  - ux
  - operator-surface
dependencies: []
priority: medium
type: enhancement
ordinal: 340000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Issue: the upgrade progress log (the M-prefixed lines an operator reads in the admin UI and journal) mixes tenses, leaves promises unresolved ('Verifying...' with no verdict), prints tribal jargon (commit subjects, 'taking ownership of the upgrade pipeline'), states resume facts three times, and claims 'complete!' before finishing its own teardown. The King annotated a real Norway upgrade log line by line during the v2026.09.0-rc.12 install and iterated a target with the foreman.

Fix: reshape every progress print to match the agreed target. The two design files are staged in git: tmp/norway-original.log (verbatim baseline, upgrade 43093 on rune) and tmp/norway-target.log (the goal picture, King-approved through four iteration rounds).

Style rules (the contract, from the iteration):
1. Present-progressive verb + ' ... ok/healthy/ready' (+ duration only when informative). The line announces the act; the ok resolves it. No unresolved promises.
2. Headlines end ':' and indent their children (Stopping services:, Installing <v>:, Checking service state:, Verifying health:, Finishing:).
3. Every hand-undoable act gets an indented artifact line: 'ran: <exact SQL>', 'wrote: <path>', 'removed: <path>'. Show what was done so an operator can invert it; never instruct.
4. Symmetric teardown: a 'Finishing:' block undoes SQL-block, maintenance, lock in reverse entry order, each with its artifact line. 'Upgrade to <v> complete.' is the canonical LAST line.
5. ~/-relative paths (deploy user's home), never machine absolutes.
6. Log granularity mirrors code granularity: batch op = one line (compose up), per-item loop = per-item results (health checks). Never invent detail, never hide available detail.
7. Migrations: 'Applying database migrations: <N> pending ... ok' — count known before apply (runUp computes len(pending)).
8. No commit subjects, no team jargon ('storm-size retry knobs', 'planned handoff'), no duplicate facts.
9. Maintenance flag content: line 1 'upgrade <id> to <version>', line 2 compact to_json (json type — jsonb reorders keys; to_json preserves SELECT order) of the immutable columns (id, commit_version, commit_sha, from_commit_version, started_at), line 3 the psql command extracting live mutable state (state, completed_at, rolled_back_at, error). Immutable facts frozen, mutable facts behind the command — the file can never lie.

Grounding: tmp/347-grounding.md (researcher-produced) maps every target line to its current print site file:line with change-class (rewording/restructure/new-data/sequencing), inventories unexercised prints (rollback/recovery/error paths) that must adopt the same rules, and resolves the sequencing question (config-updates currently printing after 'complete!').

(Design history: King-foreman iteration 2026-09-03 morning, four rounds on the staged target file.)
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 The upgrade progress log matches tmp/norway-target.log line for line on a happy upgrade (same facts, same order, same style)
- [ ] #2 Style rules applied to ALL prints in the same progress stream, including rollback/recovery/error paths (inventoried in the grounding doc)
- [ ] #3 Maintenance flag file contains: headline line, to_json (json not jsonb) ordered dump of immutable columns, psql extractor command for live state
- [ ] #4 Completion line 'Upgrade to <v> complete.' is the last line; the Finishing: block undoes lock/SQL-block/maintenance symmetrically before it
- [ ] #5 No gate or upgrade LOGIC changes beyond honest print reordering documented in the grounding
<!-- AC:END -->
