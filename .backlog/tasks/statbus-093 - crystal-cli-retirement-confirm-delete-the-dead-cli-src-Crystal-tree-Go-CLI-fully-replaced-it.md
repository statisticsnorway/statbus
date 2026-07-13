---
id: STATBUS-093
title: >-
  go-worker: recreate the Crystal worker in Go, then delete cli/src/ — end the
  Crystal/Go overlap
status: To Do
assignee: []
created_date: '2026-06-18 17:05'
updated_date: '2026-07-13 12:13'
labels:
  - tooling
  - worker
  - go-port
  - not-install-upgrade
dependencies: []
ordinal: 93000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
> NORTH STAR: one language for the CLI + worker. The `sb` Go binary already owns config/migrations/ops (it replaced manage.cr); the worker is the last Crystal holdout. Recreate it in Go, then delete cli/src/ entirely — no service runs two languages, no dead-but-compiled Crystal shadows the live Go.
> RESHAPED (King, 2026-07-13): the original "delete the dead Crystal tree" premise was REFUTED — cli/src/ is the LIVE worker (builds the production statbus-worker image, running on every box; the mechanic's pre-delete sweep caught it, comment #1). The real state: cli/src/ holds BOTH the live worker AND Crystal code (dotenv.cr/config.cr) whose job the Go CLI now ALSO does — a genuine overlap. Two ways out; the King chose the first.
> COMPLEXITY: engineer-substantial — a real port + a proof, then the deletion.
> DEPENDS ON: nothing.

THE OVERLAP (why this is not hygiene): cli/src/ compiles ONE Crystal binary `statbus worker` from cli.cr → {dotenv, config, import, worker}.cr, built by cli/Dockerfile (Crystal toolchain, `shards build`) as the worker image (images.yaml:60, release.yaml:68). The Go CLI (cli/internal/, cli/cmd/) independently reimplements dotenv/config/migration/ops — so config parsing, .env handling, etc. exist in BOTH languages, maintained twice, able to drift. The worker's actual job (doc/worker.md §1: a long-running process that listens for NOTIFY and calls worker.process_tasks()) is the only part with no Go equivalent.

THE DECISION (King, 2026-07-13): TWO options, he chose RECREATE-IN-GO.
- CHOSEN — recreate the worker in Go: port worker.cr's task-processing loop + NOTIFY listener into the Go tree (reuse the existing Go dotenv/config/migration code — no duplication), build the worker image from Go (cli/Dockerfile.sb-style, no Crystal toolchain), then DELETE cli/src/ + cli/lib/ (9 vendored shards) + shard.yml/lock + the Crystal Dockerfile path. Rationale (King): "this is the age of AI, and AI is good with Go" — a Go worker is far more maintainable by this team than Crystal. (Not chosen: trim cli/src/ down to only the worker, removing the Go-duplicated Crystal — leaves two languages forever.)

SCOPE (engineer to detail, architect to review the port design first):
1. Map worker.cr + its real dependencies (what of import.cr/dotenv.cr/config.cr the worker path actually uses vs what the Go CLI already provides).
2. Port the worker: the NOTIFY-listen loop, worker.process_tasks(), the task/queue model (cross-check the worker's structured-concurrency model in doc/worker-structured-concurrency.md + doc/derive-pipeline.md — the Go port must preserve the ONE-top-level-task-per-queue + scoped-parallel-children semantics, not just the surface behavior).
3. Build the worker image from the Go binary; retire the Crystal Dockerfile/shards path (images.yaml + release.yaml worker matrix entries point at the Go build).
4. PROVE equivalence on a real box: the Go worker processes the same task types with the same concurrency semantics as the Crystal worker (the derive pipeline still runs correctly) — a real run, not just unit tests.
5. Only after the Go worker is proven live: delete cli/src/, cli/lib/, shard.yml, shard.lock, and sweep doc/comment references (doc/worker.md updated to the Go worker).

NON-NEGOTIABLE: the Crystal worker is NOT deleted until the Go worker is proven equivalent on a real box. No overlap window where neither is authoritative.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Architect reviews the port design FIRST: the worker's real dependency surface (what it uses vs what Go already provides), and the structured-concurrency semantics the Go port must preserve (one-top-task-per-queue + scoped parallel children, per doc/worker-structured-concurrency.md)
- [ ] #2 The worker's NOTIFY-listen loop + task processing + the derive pipeline are ported to Go, reusing the existing Go dotenv/config/migration code (no re-duplication)
- [ ] #3 The worker image builds from the Go binary; the Crystal Dockerfile/shards path is retired from images.yaml + release.yaml
- [ ] #4 PROVEN on a real box: the Go worker processes tasks with the same concurrency semantics as Crystal (the derive pipeline runs correctly) — the run is the oracle
- [ ] #5 Only after that proof: cli/src/, cli/lib/, shard.yml, shard.lock deleted and doc/comment references swept (doc/worker.md updated to the Go worker) — zero Crystal/Go overlap remains
<!-- AC:END -->

## Comments

<!-- COMMENTS:BEGIN -->
author: mechanic (relayed by foreman)
created: 2026-07-13 09:55
---
PREMISE REFUTED AT EXECUTION (mechanic verification sweep, 2026-07-13) — NOTHING DELETED. cli/src/ is the LIVE source of the production WORKER image, built by CI today: images.yaml:60 + release.yaml:68 build {name: worker, context: ./cli, file: ./cli/Dockerfile}; that Dockerfile installs the Crystal toolchain, `shards build statbus --release`, CMD [/app/bin/statbus, worker]; all five .cr files compile into that one binary (cli.cr requires dotenv/config/import/worker); doc/worker.md §1 documents worker.cr as the CURRENT architecture; the built image (statbus-worker:23101161) is running on this machine right now; cli/lib/ (9 vendored shards) is required by the same build; test/test_concurrent_worker.sh/.py stat-compare cli/src/worker.cr as a second live consumer. WHAT IS TRUE: the Go CLI replaced manage.cr's territory (config/migrations/ops — the 'Ported from Crystal' comments in cli/internal confirm), and no obviously-dead individual file exists inside cli/src/. RE-SCOPE NEEDED (King-level): either (a) close this ticket as wrong-premise — the Crystal worker is live BY current design and its retirement is a real Go-rewrite project someone must deliberately choose, or (b) re-purpose it into that rewrite decision. The triage's 'verified zero-reference' verdict is corrected by this sweep.
---

author: foreman
created: 2026-07-13 12:13
---
RESHAPED (King, 2026-07-13) from 'delete dead Crystal tree' to 'recreate the worker in Go, then delete Crystal'. The original premise was refuted (cli/src/ is the LIVE worker — comment #1); the King ruled the real fix is to end the Crystal/Go OVERLAP, and chose recreate-in-Go over trim-to-worker-only: 'this is the age of AI, and AI is good with Go' — a Go worker is maintainable by this team in a way Crystal is not (his words: he personally loves Crystal, but the age of AI decides it). Priority medium, engineer-substantial, NOT on the current release critical path. Hard gate: the Crystal worker is not deleted until the Go worker is proven equivalent on a real box (the derive pipeline runs with the same structured-concurrency semantics) — no window where neither is authoritative.
---
<!-- COMMENTS:END -->
