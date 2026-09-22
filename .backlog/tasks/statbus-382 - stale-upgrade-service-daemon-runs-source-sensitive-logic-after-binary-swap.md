---
id: STATBUS-382
title: >-
  stale upgrade-service daemon runs source-sensitive logic after binary swap
status: To Do
assignee: []
created_date: '2026-09-22 17:01'
updated_date: '2026-09-22 17:01'
labels:
  - upgrade
  - recovery
  - cli
dependencies: []
references:
  - STATBUS-377
  - a96751064
priority: high
type: bug
ordinal: 24
---

## Incident

Norway attempted rc.28 while its checkout, on-disk `sb`, generated environment,
and serving containers were rc.20. The running
`statbus-upgrade@statbus.service` process was instead a deleted rc.18 executable:
`/proc/<pid>/exe` pointed to `sb (deleted)`, its hash differed from the on-disk
binary, and embedded strings identified rc.18.

Rc.18's pre-pull source capture runs `docker compose config --format json`
without `--profile all`. Norway's `app` service is profile-gated, so the stale
daemon emitted `restored source compose config has no image for app`. Commit
`a96751064` fixed this in rc.19 and later binaries, but the resident rc.18 daemon
continued executing its captured code after the on-disk swap.

The failure occurs before claim, target pull, backup, migration, or recovery
accounting. Rc.18 sends it through ordinary failure/reclaim rather than the park
path. Attempts repeated every 1-2 seconds: 190 attempts were observed, then
360 attempts per 10 minutes. The row kept `recovery_attempts=0`,
`recovery_parked_at=NULL`, and `failure_code=NULL`.

## Durable guard work

1. Before source-sensitive dispatch, assert that the running daemon identity
   (`/proc/self/exe`, embedded version/commit, and deleted-executable state)
   matches the on-disk `sb` and worktree identity. A mismatch refuses dispatch
   before stale source logic can run.
2. Reconcile a successfully replaced on-disk binary with the supervised upgrade
   service at a lifecycle boundary that does not interrupt a live upgrade.
3. Classify pre-claim deterministic failures as bounded park-class outcomes,
   with a causal failure code and daemon/tree provenance. They must not return
   the same candidate to an unbounded automatic reclaim loop.
4. Add an executable regression that starts an rc.18 daemon, advances the
   on-disk binary/tree/serving stack to rc.20 without restarting that process,
   schedules a profile-gated target, and proves bounded refusal or handoff.

## Done when

The daemon cannot execute source-sensitive upgrade logic under a mismatched or
deleted executable, pre-claim deterministic failures are bounded and recorded,
and the stale-rc.18/rc.20-tree regression passes through the real supervised
register/schedule/service path.
