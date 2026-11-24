---
id: kkj0mn
title: "Branch fast-tests fit in their time limit: build images once, not per run"
state: todo
type: feature
priority: ""
assignee: []
labels: []
group: ""
rank: "00000000000e"
created: 2026-11-24
updated: 2026-11-24
---

## Goal
A fast-tests run started by hand on a branch finishes within its job time limit with room to spare.

## Purpose
A dispatched branch run builds every image itself (docker compose up -d --build, 10-12 min) where master's runs pull prebuilt images (30 s); with timeout-minutes: 30 the job had no margin left. Run 45426056166 on feat/units-on-map (z2qt08) passed the SQL suite and live-database tests, then hit the limit 11 s into its last step and showed as cancelled.

## Principle
The branch run tests the same images it would ship; the limit stays a guard against hangs, not a race against image building.

## Details
Options: let workflow_dispatch use the Images workflow's commit-tagged images when they exist (fall back to build), cache the docker build layers, or give the build its own step outside the timed test budget. .github/workflows/fast-tests.yaml lines 146-151 (concurrency, timeout-minutes: 30) and 239-252 (Start services). Seen 2026-11-24: Start services 15:30:28-15:42:05 on the branch vs 15:11:39-15:12:09 on master.

## Depends on

## Acceptance
- [ ] A dispatched fast-tests run on a branch with migrations finishes with conclusion success, its Start services step under 3 minutes or its build step outside the test time limit

## Notes
