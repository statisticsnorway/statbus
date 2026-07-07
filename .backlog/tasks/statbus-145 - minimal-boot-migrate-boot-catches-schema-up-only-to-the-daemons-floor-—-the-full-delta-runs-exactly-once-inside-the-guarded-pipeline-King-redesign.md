---
id: STATBUS-145
title: >-
  minimal-boot-migrate: boot catches schema up only to the daemon's floor — the
  full delta runs exactly once, inside the guarded pipeline (King redesign)
status: To Do
assignee:
  - architect
created_date: '2026-07-07 09:23'
labels:
  - upgrade
  - recovery
  - design
  - product
  - needs-king-ratification
  - install-recovery
dependencies: []
references:
  - doc-027
  - doc-021
  - STATBUS-096
  - STATBUS-044
  - STATBUS-144
  - cli/internal/upgrade/service.go
  - cli/internal/migrate/migrate.go
  - cli/cmd/install_upgrade.go
  - cli/cmd/migrate.go
priority: high
ordinal: 146000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
> NORTH STAR: startup migrates the schema only to the daemon's own operating floor; every upgrade's real migration delta runs EXACTLY ONCE, inside the guarded pipeline step where counting, classification, the ceiling, park, and data-safe rollback already live. No migration runs "blindly at startup".
> BENEFIT: kills the runaway double-fire (today a runaway migration burns 2×12h — boot-migrate fire + pipeline re-fire — before rollback: the King's cost observation), makes a mid-delta failure terminal in ONE occurrence via the existing observed-state rule (schema positively Behind + pre-completion → snapshot restore), dissolves the "blind at startup" objection structurally, and shrinks the 144 flagless-churn class to floor migrations only.
> STAGE: Stage 1 — design for the King's ruling (rule together with the 096 #6 evidence probe; comment #2 shows how they compose).
> COMPLEXITY: engineer-substantial but cheap at the core — the bounded migrate form ALREADY EXISTS (`./sb migrate up --to <version>`, cmd/migrate.go:163; migrate.Up honors migrateTo, migrate.go:766-768). The work is the floor derivation + guard test + two boot sites + scenario/doc updates. No schema change.
> DEPENDS ON: nothing hard. RESHAPES: STATBUS-096 (OOM contract), STATBUS-144 (classification site), STATBUS-044 (park-scenario kill window), doc-021 (step list + budget-boundary narrative).

KING'S DIRECTION (verbatim, 2026-07-07): "So 'boot-migrate' seems to be too much. Why couldn't you upgrade to the last commit that contains the first migration that we really need for the upgrade itself to run. It gets us to the point of importance, not runs every migration? By changing this strategy, that point should be moot." And the cost observation: "The problem with out-of-memory conditions or with migrations running for an extremely long time and getting killed is that if we do it multiple times we have like twelve hours times two before we finally eat all the RAM and the process is killed or disaborted due to timeout."

READING (as designed here — the King corrects via this entry if misread): boot-migrate catches the schema up only to what the DAEMON ITSELF needs to operate. That is the schema-skew guard's real requirement by its own comment — service.go:1866-1869: "The binary's column-name expectations must match the running schema before any service-level query touches public.upgrade" — today's apply-ALL overshoots the code's own stated justification. The floor is expressed as a migration VERSION rather than a commit (same meaning, cleaner unit: migrations are linear and timestamp-versioned). The full delta then runs inside applyPostSwap's migrate step (service.go:5421) — the one site that already has write-ahead step stamping, the 12h ceiling + orphan reap (:5431-5442), exit-code classification 20/22 → park-on-first (:5449-5455), the death budget via the early guard, and the observed-state disposition (Behind → data-safe rollback).

VERDICT UP FRONT: SOUND and cheap at the core. THE SINGLE MOST IMPORTANT TRACED CONSEQUENCE (comment #2): because "at-target" is DEFINED as db.migration max ≥ on-disk max (verifyUpgradeObservedStateEx, service.go:2482-2486), moving the delta out of boot flips every mid-delta failure disposition from "forward retry" to "positively Behind → one-shot snapshot restore". Upgrades become effectively ATOMIC: apply the delta once; any death or failure mid-delta restores the pre-upgrade snapshot (data-safe: maintenance on, read-only window on, stopped-DB backup); the operator re-triggers deliberately. That is exactly the King's stated posture — and it is a deliberate contract change that must be named, not slipped in.

Full analysis: comment #1 (floor mechanism, bounded form, what it dissolves), comment #2 (costs/risks, ordering trace, the atomicity flip, composition with the 096 evidence probe, build order).
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 King ratifies: the floor strategy, the atomicity flip (mid-delta failure → one-shot rollback via the existing Behind rule), and the flagless floor-only semantics (pending-above-floor logged loud, applied only by deliberate upgrade/install)
- [ ] #2 Floor mechanism shipped: derived from the daemon-relation set (public.upgrade, db.migration, public.system_info + builder-verified enumeration), sufficiency enforced mechanically (CI guard: migration touching the set ⇒ floor bump) + an empirical floor test (schema at exactly floor; daemon boot+recovery queries run 42703-clean); existing 42703 fail-opens retained as backstop
- [ ] #3 Both boot sites switch to the bounded form (service.go:1934, install_upgrade.go:290 → migrate up --to FLOOR); the deliberate install step-table Migrations step stays apply-all (cmd/install.go:623)
- [ ] #4 Oracles re-proven: ceiling arc single-fire (1×ceiling → rolled_back, not 2×), OOM arc terminal rolled_back on first kill, park scenario kill window moved back to the pipeline migrate step
- [ ] #5 doc-021 step list + budget-boundary narrative + both diagrams updated in the same commit as the shipped change (docs describe the present)
<!-- AC:END -->
