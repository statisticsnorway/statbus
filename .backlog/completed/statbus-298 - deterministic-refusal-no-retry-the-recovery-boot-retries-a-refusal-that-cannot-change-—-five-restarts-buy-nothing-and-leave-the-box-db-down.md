---
id: STATBUS-298
title: >-
  deterministic-refusal-no-retry: the recovery boot retries a refusal that
  cannot change — five restarts buy nothing and leave the box db-down
status: Done
assignee: []
created_date: '2026-08-28 11:57'
updated_date: '2026-08-28 22:05'
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

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
CLOSED at c18e75200 (9 files, +550/−4). Built exactly to the architect's amended ruling with the checkpoint discipline holding end to end: site = the failure branch at the recovery boot's config-generate call (the mechanic's reframe — the refusal never destroyed, it prevented restoration — accepted into the ticket's model); discriminator = SENTINEL, structural not textual: one newRefusal constructor at all three refusal sites, Unwrap()-based errors.Is with the operator text verbatim, exit 78 as the process-boundary contract documented independently on both sides per the exit-42 precedent; RestartPreventExitStatus=78 reserved for principled refusals only. THE FREEZE'S BEST JUDGMENT: clear-on-success moved from the daemon pre-flight (his first draft) to config generate's own command — the ONE convergence point every caller crosses — after he caught that install's step-table invokes config generate through a separate path his first clear would never touch. install surfaces the marker as an informational banner, deliberately NO new state-ladder state. TestNoSilentNotesInInstall earned its keep (flagged a fmt.Printf diagnostic; corrected to the guard's required shape). Tests across three packages incl. a new no-prior-coverage refusal site pinned, structural ordering test on the boot branch, exit-classification against every shape; full suites + -race green in all three. North star amended honestly at the site; the serving-policy coupling remains STATBUS-307. No hard-stop needed — the threading was exactly as cheap as ruled.
<!-- SECTION:NOTES:END -->

## Comments

<!-- COMMENTS:BEGIN -->
author: architect
created: 2026-08-28 21:28
---
**RULING: the design, in three parts. The first one is load-bearing and makes the second question answer itself.**

## 1. ORDERING — refuse BEFORE any teardown. This is the whole fix.

The ticket asks what "stays serving" means. **It means nothing has been stopped yet.** A configuration ambiguity is detectable from files alone, before a single service is touched — so if the check runs first, the box is exactly as it was and keeps serving with no further mechanism required.

The observed damage (`db down`) came from tearing down and then failing before bringing back up, five times. **Move the refusal ahead of the first teardown step and that damage cannot occur** — not mitigated, structurally absent.

**Requirement:** the refusal check precedes every stop/teardown action in the recovery-boot path. **The implementer reports the intended site to the foreman BEFORE editing** — placing this correctly requires reading the boot sequence, and a check placed one step too late fixes nothing while looking finished.

## 2. EXIT — an exit code systemd will not restart

Exit **78 (EX_CONFIG)** on a principled refusal, and add **`RestartPreventExitStatus=78`** to the unit. That directive exists for exactly this and needs no policy change: transient failures keep their current codes and keep restarting, so **the transient/refusal distinction lives in the exit code rather than in a weakened restart policy.**

**78 is reserved for principled refusals and nothing else.** Any failure that a retry could plausibly fix must NOT use it — the moment 78 covers a transient, the box stops recovering on its own.

## 3. REPORT — journal, plus a marker that cannot go stale

- **Journal:** name the two colliding keys, the file, and the fix. The operator reads this only if they think to look, so it must be complete rather than terse.
- **Marker file**, alongside the existing `tmp/upgrade-in-progress.json` pattern: written on refusal, **and REMOVED on any successful start.** Cleared-on-success is what makes it trustworthy — its presence then always means *the last start refused*, and it can never mislead after the config is fixed.
- **`./sb install` reads the marker and surfaces the refusal.** On a real installation this is the operator's only lever; a refusal they cannot reach through `install.sh` is a refusal they cannot act on.

**The marker is a REPORT, not a second record of intent** — the decision lives in `.env.config`; the marker only says what the last start concluded. Clearing on success is what keeps that true.

## Cost and staffing

Cheap and buildable today: one check placement, one exit code, one unit directive, one marker write/clear, one read in `install.sh`.

**Mechanic**, with the mandatory checkpoint in part 1 — report the site, then edit.
---
<!-- COMMENTS:END -->
