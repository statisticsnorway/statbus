---
id: xz3jej
title: "Erik's sample report: legal units whose top establishment has another activity"
state: "doing"
type: docs
priority: ""
assignee: ["hibiscus"]
labels: []
created: 2026-11-18
updated: 2026-11-18
doing_since: "2026-11-18T00:59"
stage: "active"
model: "claude-opus-5-5"
branch: "master"
worktree: "/Users/jhf/ssb/statbus"
---

## Goal
Erik's sample report from PR #328 is reviewed and lands in a form the owner approves: an HTML page listing legal units whose largest establishment (by employees) has a different activity category than the legal unit, with sorting, search and the establishments on expand.

## Purpose
A worked example of reading StatBus through its REST API for a real analysis question, which countries can copy (PR https://github.com/statisticsnorway/statbus/pull/328, rsbssbno, 2026-11-15).

## Principle
Erik's work is the starting point; the owner decides what lands. A sample stays outside the product: no app or schema change. Credentials stay out of git (config.js is ignored, config.example.js is the template).

## Relevant details
PR #328: doc/integration/javascript/legal_units.html (+~300 lines) and doc/integration/javascript/config.example.js; CI all green on 2026-11-15. Its own test plan: copy config.example.js to config.js with API URL and key, open the page, check loading, sorting, search and expand.

## Depends on

## Acceptance
- [ ] The page loads data from the local slot with an API key and shows legal units whose top establishment's activity differs, checked against a SQL query on the same database
- [ ] [Owner] Reviews the page and the code and decides: merge as is, merge with changes (made and shown again), or close; the answer is recorded in the notes
- [ ] The PR is merged or closed on GitHub as decided, with a comment that links this task

## Notes


## History
- 2026-11-18T00:59 todo -> doing/active (take)
