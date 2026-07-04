---
id: STATBUS-139
title: >-
  sessions-verdict-probe: step-10 Database-sessions failure verdict rides a
  single pool-limited probe — false alarm during post-upgrade reconnection burst
status: To Do
assignee: []
created_date: '2026-07-04 22:55'
labels:
  - install
  - operator-ux
  - product
  - upgrade
dependencies: []
references:
  - cli/cmd/install.go
  - STATBUS-044
priority: high
ordinal: 140000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
FOUND live in r18 (park-oracle campaign, 2026-07-05): the un-park ./sb install completed the upgrade, then FAILED at the final idempotent refresh, step 10/16 Database sessions — cleanOrphanSessions killed the two expected orphans, slept a fixed 2s, re-probed once, declared 'connection pool still saturated' and exited 1 with 'fix and re-run'. Minutes later the pool was 16/30 healthy: a transient reconnection burst from just-restarted services on a max_connections=30 box. An operator following the printed advice would trivially succeed → the failure is pure noise (the false-alarm class that erodes siren trust on headless boxes).

TWO STRUCTURAL DEFECTS (architect-verified at the source):
1. VERDICT-ROLE CONFLATION: checkSessionsClean returns conservative-FALSE on ANY error — PsqlCommand err, cmd.Output err, Atoi err, zombieAdvisoryHolders err (install.go:1325-1369). That is correct for its GATE role (can't verify → trigger cleanup) and WRONG for its VERDICT role at install.go:1510, where false means 'still saturated' → hard fail. 'Cannot verify' and 'verified dirty' are different verdicts and must not share a bool.
2. OBSERVER RIDES THE OBSERVED RESOURCE: the verdict re-probe connects via migrate.PsqlCommand — the pool-limited external path — while cleanOrphanSessions itself deliberately uses `docker compose exec -T db psql` peer-auth PRECISELY because a saturated pool refuses every external connection (install.go:1449-1455 comment). During the exact condition the verdict exists to judge, the probe's own connection fails → guaranteed false 'saturated'.

FIX SHAPE (architect): (a) the verdict probe uses the docker-exec peer-auth transport (same as the cleaner — observer independent of the observed pool); (b) split the verdict tri-state: clean / dirty(with observed counts) / unverifiable(probe error) — fail ONLY on verified-dirty, retry on unverifiable; (c) bounded settle loop replacing the single fixed 2s sleep: re-probe every ~3-5s up to ~45-60s (slot release is async; a reconnection burst on a small pool takes longer than 2s), succeed on first clean read; (d) the final failure message names WHAT was observed (leaked count, zombie pids, or probe error) — actionable, per fail-fast discipline. Distinguish 'orphans killed, pool draining' (retry) from 'genuinely wedged' (fail with evidence).

EVIDENCE: r18 kept-VM autopsy (root@89.167.23.219, pool 16/30 healthy post-hoc); scenario assertion 'un-park install exits 0' is CORRECT and stays — architect ruled AGAINST tolerating exit-1 (mushy acceptance of a real operator-facing false alarm). r19 launches after this ships; it is the last red between the park oracle and a full green.
<!-- SECTION:DESCRIPTION:END -->
