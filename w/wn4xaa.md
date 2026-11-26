---
id: "wn4xaa"
title: "CI results stored in the repository, so release checks need no GitHub API"
state: "todo"
assignee: []
labels:
  - release
  - ops
  - resilience
group: ""
rank: "000000000388"
dependencies: []
priority: "low"
type: "feature"
origin: "backlog:STATBUS-343"
aliases: ["STATBUS-343"]
backlog_type: "enhancement"
created: "2026-09-02 12:43"
design_question: "ci-verdict-ledger proposes recording workflow verdicts on a git ref so nothing polls the GitHub API (after a rate-limit incident). Build it (then it gets acceptance checks), or drop it as solved otherwise?"
design_for: "jhf"
design_since: "2026-11-22T23:31"
design_asked_by: "hibiscus"
stage: "design"
---

## Goal
Each CI workflow's result for a commit is written to a branch ci-verdicts in the repo, and release checks read it with git fetch.


## Purpose
Why: release preflight (cli/internal/release/workflow_check.go) and agents' CI watchers ask GitHub's REST API for workflow results. That API has an hourly quota; in an earlier release cut, watchers used it up and the cut stopped on HTTP 403. git fetch has no such quota, and every box already uses it.

## Principle
What: one line per finished workflow run, {sha, workflow, conclusion, run_id, finished_at}, in one file per commit, on an orphan branch refs/heads/ci-verdicts. How it gets there: a small workflow triggered by workflow_run (completed) for every CI workflow commits that line. How it is read: git fetch origin ci-verdicts, then read verdicts/<sha>.jsonl. The REST API stays only as a fallback when the line is missing. No new server, secret or daemon. Customer boxes are not affected.

## Details
Example after a push of abc123: verdicts/abc123.jsonl on branch ci-verdicts holds lines like {"sha":"abc123","workflow":"Fast Tests","conclusion":"success","run_id":45426056166,"finished_at":"2026-11-26T20:30:00Z"}. Changes: (1) .github/workflows/ci-verdicts.yaml, on workflow_run completed, appends the line and pushes (GITHUB_TOKEN with contents: write); (2) cli/internal/release/workflow_check.go reads the file first, REST as fallback; (3) the agents' CI instruction (AGENTS.md: gh run list) reads the file instead. Alternatives considered: a webhook receiver on niue (adds a secret and a daemon), or keep polling at a polite rate (no change). Priority: low unless the quota bites again.

## Acceptance
- [ ] [Owner] decides: build it, or drop it; recorded in Notes
- [ ] After a push, verdicts/<sha>.jsonl on branch ci-verdicts lists every CI workflow's conclusion within a minute of each finishing
- [ ] ./sb release preflight passes a release cut with zero GitHub REST status calls, reading the verdicts file

## Questions
- 2026-11-22T23:31 question 1 by hibiscus to jhf:
  ci-verdict-ledger proposes recording workflow verdicts on a git ref so nothing polls the GitHub API (after a rate-limit incident). Build it (then it gets acceptance checks), or drop it as solved otherwise?


## Requests
- 2026-11-26T21:40 request 1 by jhf:
  So you're can it be more concrete the goal so what why how store in the repository where how like like too much text too little clarity please
  resolved 2026-11-26T21:41 by rabbit:
    Rewritten to be concrete. Title: CI results stored in the repository. Goal in one sentence: each workflow's result is written to branch ci-verdicts and read with git fetch. Purpose: why (REST quota ran out in a release cut, git fetch has no quota). Principle: what (one line per run, one file per commit, verdicts/<sha>.jsonl on orphan branch ci-verdicts), how it is written (a workflow_run workflow commits it), how it is read (git fetch, REST only as fallback). Details: an example line, the three files it changes, the alternatives, and priority low. Checks: your build-or-drop decision, the file appearing after a push, and a release cut with zero REST calls.

## History
- 2026-11-22T23:31 todo -> todo/design (ask)
- 2026-11-26T21:40 request 1 by jhf
- 2026-11-26T21:40 request 1 delivered to rabbit (session_rabbit_1788255452439_e2c96135756f0328)
- 2026-11-26T21:41 request 1 acknowledged by rabbit
- 2026-11-26T21:41 request 1 in progress by rabbit: hug task set wn4xaa
- 2026-11-26T21:41 resolved request 1 by rabbit
