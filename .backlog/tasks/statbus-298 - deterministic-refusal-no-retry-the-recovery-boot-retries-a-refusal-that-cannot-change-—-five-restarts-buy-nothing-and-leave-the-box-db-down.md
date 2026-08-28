---
id: STATBUS-298
title: >-
  deterministic-refusal-no-retry: the recovery boot retries a refusal that
  cannot change — five restarts buy nothing and leave the box db-down
status: To Do
assignee: []
created_date: '2026-08-28 11:57'
labels:
  - upgrade
  - cli
dependencies: []
priority: high
type: bug
ordinal: 291000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
NORTH STAR: transient failure and principled refusal are different things and must not share a restart policy. A deterministic refusal must not be retried — stop cleanly, leave the box serving, name the fix.

THE FINDING (from STATBUS-297's journal, architect's ruling 2026-08-28): when the upgrade service's recovery boot hits `./sb config generate`'s refusal (a deterministic, correct, actionable refusal — ambiguous config, fail fast), it exits 1 and systemd restarts it every ~30s into the IDENTICAL failure, five times, until the rate limiter kills the unit for good. The box ends db-down and rate-limited — strictly worse than the misconfiguration being refused — and the restart budget that exists for TRANSIENT failures is burned on a failure that cannot change between attempts (the config does not edit itself).

WHY IT MATTERS IN THE REAL FRAME: on an NSO box the operator's only tool is install.sh. A box taken down by a config-key collision — where the operator's one lever may meet the same refusal — is a bricked installation from a fixable mistake.

THE RULE TO IMPLEMENT: the recovery-boot path (and any service path that can meet a refusal-class error) distinguishes refusal from transient failure. On refusal: do not exit-and-let-systemd-retry — stop cleanly in a state that leaves whatever can serve serving, surface the refusal's own actionable message (the sub-fix at 9970c983e already preserves it), and wait for the human. The refusal text itself is the remedy instruction; the service's job is to deliver it, not to retry past it.

DO NOT let this be fixed by weakening the guard: refusing on ambiguous configuration is CORRECT (unprincipled input, fail fast). What is wrong is the RETRY and the COLLATERAL, never the refusal.

ADJACENT BUT NOT THE SAME: STATBUS-111/159 park an upgrade ROW on deterministic failure at target; this is the SERVICE failing to BOOT on config. Same instinct — deterministic failures park, transient failures retry — different object. Cross-referenced both ways.

DESIGN OPEN (architect at build time): what "stop cleanly" means concretely in the recovery-boot context — the flag file's state, whether the old binary/services stay up, and how the refusal reaches the operator (journal + install.sh's next run should both show it).

WHAT IS ACHIEVED: a fixable configuration mistake can no longer brick a box; the refusal arrives as instructions instead of as a dead service.
<!-- SECTION:DESCRIPTION:END -->
