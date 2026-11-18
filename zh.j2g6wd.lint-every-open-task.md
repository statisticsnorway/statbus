---
id: j2g6wd
title: "Lint every open task once hug stops linting done tasks"
state: "doing"
type: chore
priority: ""
assignee: ["hibiscus"]
labels: []
created: 2026-11-18
updated: 2026-11-18
doing_since: "2026-11-18T00:40"
stage: "waiting"
model: "claude-opus-5-5"
branch: "master"
worktree: "/Users/jhf/ssb/statbus"
waiting_on: "the owner's decision on hug upgrade --apply (hug v0.7.53 is installed)"
waiting_since: "2026-11-18T00:40"
waiting_asked_by: "hibiscus"
---

## Goal
Every open task (todo or doing) on the StatBus board passes hug task lint, so the board's findings are all actionable.

## Purpose
Today hug lints done and dropped tasks too, and the old imported board makes hundreds of findings that hide the ones that matter (owner 2026-11-17 23:39). The owner is having hug changed so done tasks are not linted.

## Principle
Wait for the hug release that skips done tasks, then fix the open tasks one by one with the owner. Tasks another agent has taken are theirs to fix. Done tasks are left as they are.

## Relevant details
Installed now: hug v0.7.53 (brew veridit/tap/hug). Open tasks with findings: see the notes of 2026-11-18 02:55. Check with: hug task lint <id> per task, and hug upgrade for the pending mechanical changes.

## Depends on

## Acceptance
- [ ] [Owner] Decides whether to run hug upgrade --apply; the answer is recorded in the notes. Yes: run it, which moves the waits of yq5tr6, ezp3h0, mtw92d and hmgadt to asked and changes the memory hooks in the other projects' .jcode/config.toml, then re-lint. No: fix yq5tr6's old-layout field by hand and leave Rabbit's tasks to him.
- [x] With hug v0.7.53 or later installed, hug task lint reports no findings on done or dropped tasks
- [ ] hug task lint reports no findings on any open task, except tasks another agent has taken, which are named in the notes

## Notes


2026-11-18 02:55 hug v0.7.53 is installed now. hug task lint: g71vzm, q8604t, 89f3jm, ma6jcm, sdxbdr, xz3jej have no findings; yq5tr6 and ezp3h0 report old-layout waiting_for (ezp3h0 also branch-gone, it is Rabbit's). hug upgrade (preview) would move 4 waits to asked (yq5tr6, ezp3h0, mtw92d, hmgadt) and drop j2g6wd's own waiting_for, and would also change the memory hooks in other projects' .jcode/config.toml (GenderedGames, Brovs, seid, truth_tribe_and_treasure, ssb). Not applied overnight because it rewrites Rabbit's tasks and other repos' config; the owner decides whether to run hug upgrade --apply.
2026-11-18 02:56 tasks another agent has taken, left to them: Rabbit's 00rnq5, nst6hb, hmgadt, senzch, ezp3h0, 89f3jm (hmgadt and ezp3h0 are in hug upgrade's list). The tap name veridit/tap/hug is right (brew info: stable 0.7.54, newer than the 0.7.53 installed).
2026-11-18 02:57 check 2 observed with hug v0.7.53: hug task lint reports 143 findings on 50 tasks, every one of them open (64 tasks are todo or doing); none of the done or dropped tasks is among them (tmp/hug/linted-ids.txt compared with every file whose state is done or dropped). The board-wide findings to work through: 8 missing-goal, 5 old-layout, 3 branch-gone, 94 missing-section, 31 long-title, 2 no-acceptance.
## History
- 2026-11-18T00:40 todo -> doing/active (take)
- 2026-11-18T00:40 doing/active -> doing/waiting (wait)
- 2026-11-18T11:39 waiting_for jhf removed by hug upgrade (it asks nothing: no '?', no check named, no request such as approve; the wait stays, 41hhgn)
