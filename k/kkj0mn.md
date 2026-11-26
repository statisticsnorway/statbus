---
id: kkj0mn
title: "Branch fast-tests fit in their time limit: build images once, not per run"
state: todo
type: feature
priority: "low"
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
Filed by Hibiscus (map agent, z2qt08) on 2026-11-24 17:11, after its branch feat/units-on-map needed a CI run before merging. How CI runs today: on master, a push starts Images (builds commit-tagged images), and fast-tests starts when Images finishes and pulls those images (Start services ~30 s). A branch push starts nothing, because Images and fast-tests only trigger on master; to test a branch before merging, an agent dispatches fast-tests by hand (workflow_dispatch), which builds every image itself (docker compose up -d --build, 10-12 min) inside the job's 30-minute limit. Run 45426056166 on c403f37a1: attempt 1 was cancelled 11 s into its last step at the limit, attempt 2 passed. With the one-directory-per-agent workflow (2026-11-26) branches are rebased and merged to master by fast-forward, and master's push runs the full CI with prebuilt images; a branch CI run is only needed when an agent wants evidence before merging. Options if it is needed: dispatch Images for the branch first and let fast-tests use those images, cache docker build layers, or keep the build outside the timed step. .github/workflows/fast-tests.yaml lines 146-151 (timeout-minutes: 30), 239-252 (Start services).

## Depends on

## Acceptance
- [ ] A dispatched fast-tests run on a branch with migrations finishes with conclusion success, its Start services step under 3 minutes or its build step outside the test time limit

## Requests
- 2026-11-26T21:16 request 1 by jhf:
  This ticket cannot be high priority. If it was, it would have been built while we needed it. Instead, you have to explain to me which agent reported it, where are the details, what would you do? How would it interact? How would it work with this status, status A, status B, and so forth? Why don't we push to have the CI run? Something is not computing for me.

## Notes


## History
- 2026-11-26T21:16 request 1 by jhf
- 2026-11-26T21:16 request 1 delivered to rabbit (session_rabbit_1788255452439_e2c96135756f0328)
- 2026-11-26T21:16 request 1 acknowledged by rabbit
- 2026-11-26T21:17 request 1 in progress by rabbit: hug task set kkj0mn
