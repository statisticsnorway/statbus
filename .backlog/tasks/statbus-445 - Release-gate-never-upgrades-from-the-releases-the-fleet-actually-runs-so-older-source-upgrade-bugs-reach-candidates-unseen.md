---
id: STATBUS-445
title: >-
  Release gate never upgrades from the releases the fleet actually runs, so
  older-source upgrade bugs reach candidates unseen
status: To Do
assignee: []
created_date: '2026-10-03 14:55'
labels:
  - release
  - testing
  - upgrade
  - install-recovery
dependencies: []
references:
  - STATBUS-436
  - STATBUS-441
  - STATBUS-443
  - STATBUS-444
priority: high
---

## Issue

Every upgrade proof on the release ladder starts from one of two sources:
- the **newest stable**: smoke `0-happy-upgrade` installs v2026.09.3, then upgrades
- the **candidate itself**: the arcs install A = the candidate commit, then upgrade to fixture B/C

No gate ever upgrades from an **older** release. That is exactly where three bugs in a row lived. All three were found only by the on-demand STATBUS-436 proof, which happens to start on v2026.09.2:
- STATBUS-441: the inline claim uses post-382 SQL and stops at 42703 on a pre-382 schema.
- STATBUS-443: the inline capture refuses after an installer checkout leaves `.env` at the source tag.
- STATBUS-444: install crash recovery regenerates config without `--migrate-legacy-secrets` and refuses on 09.2-era `.env.config` secrets.

rc.12 and rc.13 passed every machine gate (rc.13: arcs 41/41, fleet, smoke, hardening, dev canary) while carrying these bugs.

## Evidence: the fleet is mostly on older releases (read-only probe 2026-10-03 14:53 UTC)

| box | `sb --version` | legacy secrets in `.env.config` |
|---|---|---|
| demo | v2026.09.2 | 2 |
| et | v2026.09.0 | 2 |
| ug | v2026.09.0 | 2 |
| jo | v2026.08.0 | 2 |
| ma | v2026.09.3 | 0 |
| rune (no) | v2026.09.3-rc.17 | 0 |
| dev | v2026.10.0-rc.13 | 0 |

The gate's only upgrade source (09.3) matches 2 of the 7 boxes.

## Principled fix: one rung, "upgrade from every supported source"

1. **Source matrix:** the distinct stable releases the fleet runs, with a declared floor (owner decides: the fleet's oldest, or a support window). Today that is 08.0, 09.0, 09.2 and 09.3. Each source is installed with that release's own installer, so it carries its era's real `.env.config`, credentials, schema and ledger. Nothing is synthesized.
2. **Paths per source:**
   - (a) **service path:** register + schedule, and the box's own daemon upgrades (the production norm)
   - (b) **operator path:** `./cloud.sh install <box> <tag>`'s pinned `install.sh` (the 436 `CANDIDATE_PATH=operator` shape)
   - (c) **schedule-then-installer:** the 436 `CANDIDATE_PATH=scheduled` shape, if the owner keeps it a supported route
3. **Pass criteria (436's tail):**
   - the target row is `completed`
   - data counts unchanged
   - checkout, binary and resident daemon all at the target
   - db/app/worker/proxy at the target
   - healthy across ≥3 scheduler ticks with no unit restarts
   - no retry loop
4. **Execution:** the existing LXD fleet host. One installed checkpoint per source release (built once per candidate cycle, reusable while the source is unchanged), forked per path. The cost is about 5–10 min per cell, inside the existing `LXD_HOST_SLOTS` budget.
5. **Gate:** `./sb release stable` requires the whole matrix green at the candidate commit, same contract as the arc harness (`WorkflowLXDFleet` style, no per-cell inheritance until STATBUS-352/353 coverage says otherwise).

## Owner questions (block only the parts noted)

- Q1: is "schedule, then `install.sh` / `./sb install`" a supported operator route? AGENTS.md documents "schedule, then `./sb install` to dispatch immediately". If yes, path (c) is in every cell. If no, the docs change and (c) leaves the matrix.
- Q2: what is the source floor: whatever the fleet runs (jo's 08.0 today), or a declared window (e.g. the last 3 stables)?

## Acceptance criteria

- [ ] #1 A source-matrix workflow on the LXD host installs each source release with its own installer, upgrades each to the candidate by every supported path, and asserts the pass criteria above per cell.
- [ ] #2 The source list is derived, not hand-maintained: the fleet's distinct stable versions plus the declared floor, resolved at cut time and printed in the run summary.
- [ ] #3 Proven RED/GREEN: against v2026.10.0-rc.13, the 09.2 source cell on path (c) fails with STATBUS-444's refusal, and against the candidate carrying the 444 fix it passes.
- [ ] #4 `./sb release stable` refuses unless the matrix run is green at the candidate commit. The ladder doc gains the rung with what it proves and what it may skip.
