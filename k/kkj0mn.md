---
id: kkj0mn
title: "Branch fast-tests fit in their time limit: build images once, not per run"
state: todo
type: feature
priority: "low"
assignee: ["hibiscus"]
labels: []
group: ""
rank: "00000000000e"
created: 2026-11-24
updated: 2026-11-24
---

## Goal
A fast-tests run started by hand on a branch finishes within its job time limit with room to spare.

## Purpose
A fast-tests run started by hand on a branch builds every image inside its timed job, so it runs out of time before the tests finish and shows as cancelled although nothing failed.

## Principle
The branch run tests the same images it would ship; the limit stays a guard against hangs, not a race against image building.

## Details
Filed by Hibiscus (map agent, z2qt08) on 2026-11-24 17:11, after its branch feat/units-on-map needed a CI run before merging. How CI runs today: on master, a push starts Images (builds commit-tagged images), and fast-tests starts when Images finishes and pulls those images (Start services ~30 s). A branch push starts nothing, because Images and fast-tests only trigger on master; to test a branch before merging, an agent dispatches fast-tests by hand (workflow_dispatch), which builds every image itself (docker compose up -d --build) inside the job's 30-minute limit (.github/workflows/fast-tests.yaml lines 146-151 timeout-minutes: 30, 239-252 Start services). Runs: 45426056166 on c403f37a1 (2026-11-24): build 10-12 min, attempt 1 cancelled 11 s into its last step at the limit, attempt 2 passed. 45922674956 on 9552ec592 (2026-11-27): image build ~22 min, SQL fast suite all 146 + 3 isolated passed, then cancelled at the limit in the Go live-database tests. With the one-directory-per-agent workflow (2026-11-26) branches are rebased and merged to master by fast-forward, and master's push runs the full CI with prebuilt images; a branch run is only needed for evidence before merging. Options: dispatch Images for the branch first and let fast-tests pull those images; cache docker build layers; keep the build outside the timed step.

## Depends on

## Acceptance
- [ ] A dispatched fast-tests run on a branch with migrations finishes with conclusion success, its Start services step under 3 minutes or its build step outside the test time limit
- [ ] [Owner] Decides whether branch runs should fit their time limit (build it) or branch evidence relies on master's CI after the fast-forward (drop this task); the answer is recorded in this task's notes
- [ ] If built: a dispatched fast-tests run on a branch with migrations ends with conclusion success, and the image build does not count against the test job's 30-minute limit

## Requests
- 2026-11-26T21:16 request 1 by jhf:
  This ticket cannot be high priority. If it was, it would have been built while we needed it. Instead, you have to explain to me which agent reported it, where are the details, what would you do? How would it interact? How would it work with this status, status A, status B, and so forth? Why don't we push to have the CI run? Something is not computing for me.
  resolved 2026-11-26T21:17 by rabbit:
    Priority set to low. Details now say who filed it (Hibiscus, map work z2qt08, 2026-11-24), how CI runs on master versus a branch, why a branch run builds its own images and hits the 30-min limit (only master pushes trigger Images and fast-tests; a branch needs a manual dispatch), and how it fits the one-directory workflow: branches merge to master by fast-forward and master's push runs CI, so a branch run is only for evidence before merging.

## Notes


Owner 2026-11-26 20:21: handed to Hibiscus, who filed it; the owner decides with Hibiscus whether to build it or drop it.
2026-11-27 run 45922674956 (feat/units-on-map): fast suite passed in ~22 min after a ~22-min image build; the job was cancelled at its 30-minute limit in the Go live-database tests. Evidence for this task.
## History
- 2026-11-26T21:16 request 1 by jhf
- 2026-11-26T21:16 request 1 delivered to rabbit (session_rabbit_1788255452439_e2c96135756f0328)
- 2026-11-26T21:16 request 1 acknowledged by rabbit
- 2026-11-26T21:17 request 1 in progress by rabbit: hug task set kkj0mn
- 2026-11-26T21:17 resolved request 1 by rabbit
