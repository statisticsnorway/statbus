---
id: j2g6wd
title: "Lint every open task once hug stops linting done tasks"
state: "todo"
type: chore
priority: "high"
assignee: ["hibiscus"]
labels: []
group: ""
rank: "000000000004"
created: 2026-11-18
updated: 2026-11-18
stage: "ready"
model: "claude-opus-5-5"
branch: "master"
worktree: "/Users/jhf/ssb/statbus"
---

## Goal
hug task lint reports no findings on any open task, except tasks another agent has taken, which are named in the notes.

## Purpose
Lint findings on open tasks hide the ones that matter: a task missing its goal or acceptance cannot be worked or checked.

## Principle
Fix the open tasks one by one, with the owner where a task needs his design. Tasks another agent has taken are theirs to fix. Done tasks are left as they are.

## Relevant details
Installed: hug v0.7.84; hug upgrade reports nothing pending (applied 2026-11-19), hug setup is all green, and the owner upgrades hug continuously, so each release's lint rules apply to the open board. Since v0.7.53 hug lints open tasks only. Open tasks with findings 2026-11-19: 43 (82 missing-section, 30 long-title, 4 missing-goal, 2 no-acceptance, 1 wait-on-person, 1 doing-idle). Check with: hug task lint, hug task lint <id>, hug task lint --code CODE. Order (owner 2026-11-19): after the feature tickets m6mnnw, e1z8va, 64ae2w, z2qt08, 2gpcs7 and xhxnsy.

## Depends on

## Acceptance
- [x] [Owner] Decides whether to run hug upgrade --apply; the answer is recorded in the notes. Yes: run it, which moves the waits of yq5tr6, ezp3h0, mtw92d and hmgadt to asked and changes the memory hooks in the other projects' .jcode/config.toml, then re-lint. No: fix yq5tr6's old-layout field by hand and leave Rabbit's tasks to him.
- [x] With hug v0.7.53 or later installed, hug task lint reports no findings on done or dropped tasks
- [ ] hug task lint reports no findings on any open task, except tasks another agent has taken, which are named in the notes

## Requests
- 2026-11-19T16:28 request 1 by jhf:
  Please, we upgrade continuously. Run the upgrade for the love of all that is good, right?
  resolved 2026-11-19T16:30 by hibiscus:
    Ran it: hug upgrade --apply (v0.7.84; hooks and MCP entries everywhere now run hug, nothing left pending), and AGENTS.md/CLAUDE.md took this hug's Tasks section (68973051e), so hug setup is all green. From now on I apply hug upgrades as they come, without asking. Check 3 (lint every open task: 43 tasks with findings) is still open and queued after the feature tickets.

## Notes


2026-11-18 02:55 hug v0.7.53 is installed now. hug task lint: g71vzm, q8604t, 89f3jm, ma6jcm, sdxbdr, xz3jej have no findings; yq5tr6 and ezp3h0 report old-layout waiting_for (ezp3h0 also branch-gone, it is Rabbit's). hug upgrade (preview) would move 4 waits to asked (yq5tr6, ezp3h0, mtw92d, hmgadt) and drop j2g6wd's own waiting_for, and would also change the memory hooks in other projects' .jcode/config.toml (GenderedGames, Brovs, seid, truth_tribe_and_treasure, ssb). Not applied overnight because it rewrites Rabbit's tasks and other repos' config; the owner decides whether to run hug upgrade --apply.
2026-11-18 02:56 tasks another agent has taken, left to them: Rabbit's 00rnq5, nst6hb, hmgadt, senzch, ezp3h0, 89f3jm (hmgadt and ezp3h0 are in hug upgrade's list). The tap name veridit/tap/hug is right (brew info: stable 0.7.54, newer than the 0.7.53 installed).
2026-11-18 02:57 check 2 observed with hug v0.7.53: hug task lint reports 143 findings on 50 tasks, every one of them open (64 tasks are todo or doing); none of the done or dropped tasks is among them (tmp/hug/linted-ids.txt compared with every file whose state is done or dropped). The board-wide findings to work through: 8 missing-goal, 5 old-layout, 3 branch-gone, 94 missing-section, 31 long-title, 2 no-acceptance.
2026-11-19 16:29 owner (request 1): upgrade continuously, without asking. Done: hug upgrade --apply --machine (hug v0.7.84; hooks and MCP entries in ~/.jcode, ~/.claude and five project .jcode/config.toml now run hug, backups *.bak-hug-upgrade; board layout and tasks had nothing to do); hug upgrade now reports nothing to do. hug setup's last open step, the agent instructions, done in 68973051e (AGENTS.md and CLAUDE.md take v0.7.84's Tasks section verbatim). Coordinator set to hibiscus earlier today. Check 3 (lint every open task) remains: 43 open tasks, findings 82 missing-section, 30 long-title, 4 missing-goal, 2 no-acceptance, 1 wait-on-person, 1 doing-idle.
2026-11-19 16:30 back to todo: queued after the feature tickets the owner asked to land first (m6mnnw is doing); the upgrade wait is over.
## History
- 2026-11-18T00:40 todo -> doing/active (take)
- 2026-11-18T00:40 doing/active -> doing/waiting (wait)
- 2026-11-18T11:39 waiting_for jhf removed by hug upgrade (it asks nothing: no '?', no check named, no request such as approve; the wait stays, 41hhgn)
- 2026-11-19T16:28 request 1 by jhf
- 2026-11-19T16:28 request 1 delivered to hibiscus (session_hibiscus_1793348926173_ffff8733f4ad20e1)
- 2026-11-19T16:28 request 1 acknowledged by hibiscus
- 2026-11-19T16:30 request 1 in progress by hibiscus: hug task note j2g6wd "2026-11-19 16:29 owner (request 1): upgrade continuously, without asking. Done: hug upgrade --apply --machine (hug v0.7…"
- 2026-11-19T16:30 resolved request 1 by hibiscus
- 2026-11-19T16:30 doing/waiting -> todo/ready (give back; was assignee: hibiscus); was doing_since: 2026-11-18T00:40; waiting_asked_by: hibiscus; waiting_on: the owner's decision on hug upgrade --apply (hug v0.7.53 is installed); waiting_since: 2026-11-18T00:40
