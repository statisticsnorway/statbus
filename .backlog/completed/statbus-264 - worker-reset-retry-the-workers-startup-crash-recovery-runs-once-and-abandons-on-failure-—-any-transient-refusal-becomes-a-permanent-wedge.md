---
id: STATBUS-264
title: >-
  worker-reset-retry: the worker's startup crash recovery runs once and abandons
  on failure — any transient refusal becomes a permanent wedge
status: Done
assignee: []
created_date: '2026-08-27 12:48'
updated_date: '2026-08-27 13:15'
labels:
  - worker
dependencies: []
priority: high
type: bug
ordinal: 257000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
From STATBUS-262 (Norway wedge): worker.reset_abandoned_processing_tasks() runs exactly once per worker startup; when it failed (refused inside the upgrade's read-only window), it logged ERROR and never ran again, leaving four 'processing' rows wedged for a week behind a healthy-looking worker.

Architect's PRIMARY structural fix: the reset must RETRY until it succeeds, not log-and-abandon — a once-per-startup recovery that can fail permanently converts ANY transient condition (this window, a slow database, a blip) into a permanent wedge. Additionally ruled: a failed startup crash-recovery must never be merely logged — either it retries until success, or the worker refuses to report healthy.

Evidence and full root cause: STATBUS-262 comments #3-#5 (worker started +0.3s before its recovery call, window lifted +2.4s after start, RestartCount=0 since).

WHAT IS ACHIEVED: no transient startup condition can permanently disable the worker's crash recovery, and a recovery that cannot run is loud instead of silent.
<!-- SECTION:DESCRIPTION:END -->

## Comments

<!-- COMMENTS:BEGIN -->
author: engineer
created: 2026-08-27 13:04
---
**BUILT AND FROZEN.** One file: `cli/src/worker.cr`. Type-checks clean through the entrypoint with ZERO warnings; the Go side is untouched and still green.

**FIRST, A FACT THE TICKET DOES NOT STATE: the worker is CRYSTAL, not Go.** `docker-compose.worker.yml` builds from `./cli`, and `cli/Dockerfile` installs Crystal and runs `/app/bin/statbus worker` — the live Crystal worker. The call is at `cli/src/worker.cr:378-388`, inside the block that has just acquired the global advisory lock.

## The fix

The old shape was `begin … rescue ex; @log.error; end`, falling straight through into `start_queue_discovery`. It now retries with exponential backoff (1s, doubling, capped at 15s) against a 5-minute budget, and if the budget is exhausted it logs FATAL and **exits**.

Both arms of the ruling, and the second is the one that matters: `restart: unless-stopped` turns the exit into a VISIBLE CRASH-LOOP rather than a worker that silently skipped its crash recovery and then looks healthy forever. A worker that cannot recover must not claim to be working.

The budget is deliberately generous against the observed failure (Norway needed 2.4 seconds) and deliberately finite, so a genuinely broken database becomes visible within minutes instead of a worker sitting forever pretending to start. The retry is `@shutdown`-aware and waits through `wait_with_shutdown_check`, so a stop signal during the window is still honoured. The warning names the upgrade window explicitly, because a brief refusal during an upgrade is EXPECTED and a responder should not be alarmed by one line of it.

## MY FIRST VERIFICATION WAS WORTHLESS, AND I PROVED IT RATHER THAN TRUSTED IT

I ran `crystal build --no-codegen src/worker.cr`, got exit 0, and nearly reported it as verified. Then I mutated the code to reference an undefined symbol and re-ran: **still exit 0**. Crystal only type-checks REACHABLE method bodies, so compiling the library file alone analyses nothing inside a method nobody calls from there.

Building through the ENTRYPOINT (`src/statbus.cr`) does bite: the same mutation exits 1 and names my line. Every check reported here is the entrypoint build. Had I trusted the first result I would have shipped unverified Crystal to a production worker on the strength of a green that examined nothing.

## AND THAT REAL CHECK CAUGHT SOMETHING

The entrypoint build warned that `Time.monotonic` is DEPRECATED in Crystal 1.20.2. The codebase already anticipated this: `cli/src/cli.cr:13-21` defines a `Statbus.monotonic_time` macro that picks `Time.instant` on 1.19+ and `Time.monotonic` below — written precisely because the container's Crystal version is not the developer's. `worker.cr` already uses that macro in six places; my two uses now do too, matching the file's own convention. Using the raw form would have been a warning locally and a real risk in the alpine build.

## WHAT I COULD NOT VERIFY, STATED PLAINLY

There is no working Crystal test suite. `cli/spec/statbus_spec.cr` fails to compile on master — `undefined constant StatBus` (the module is `Statbus`) — so `crystal spec` does not run at all, and has not for some time. Pre-existing, not touched by me, but it bounds the confidence here honestly: **my only automated oracle for this change is the type-checker.** The retry loop's behaviour under a real refusal is unproven until a run exercises it. Probably worth its own entry.
---

author: engineer
created: 2026-08-27 13:11
---
**AMENDMENT APPLIED AND RE-FROZEN.** Entrypoint type-check clean, zero warnings.

The exhaustion message no longer names the upgrade window as if it were the only cause. It now opens with the question a responder should ask FIRST — is the database read-only ON PURPOSE? — gives the one command that answers it (`SHOW default_transaction_read_only;`), and names all three deliberate cases: the upgrade's accident-guard window (clears itself), an upgrade held in its post-failure ABORT state awaiting an operator decision (`./sb install` resolves it), and an administrator's hand-set maintenance. It states plainly that in every one of those the worker is CORRECTLY refusing and will start on its own once the database is writable, and closes with the discriminator: only if the database is NOT read-only is the error above a real fault worth chasing.

That matters because the exit is a crash-loop. Without it, a responder meeting a looping worker on a box that is read-only for a perfectly good reason would go hunting a worker bug that does not exist — and the loop itself would look like the evidence.

RE-VERIFIED that the check reaches the amended text: mutating a line inside the new message fails the entrypoint build naming it (line 499). Reversed; clean afterwards.

**RECORDED AS UNPROVEN, per the ruling:** this retry loop will not be exercised by rc.10. Once STATBUS-265 lands the reset is never refused, so no normal upgrade reaches the retry path at all — proof waits on STATBUS-270 or deliberate fault injection. Worth stating in the ticket rather than only in a message, because a future reader will otherwise assume a release that shipped it also tested it.
---
<!-- COMMENTS:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Landed at ca6b7082d together with STATBUS-265 (architect: LAND as one commit — the code interleaves and 264 alone would crash-loop a box legitimately holding the abort-hold). The startup crash recovery retries with backoff (1s doubling, 15s cap, 5-minute budget); on exhaustion it exits FATAL so restart:unless-stopped produces a visible crash-loop instead of a silently skipped recovery. The exhaustion message is diagnostic-first: is the database read-only ON PURPOSE (window / abort-hold / maintenance), with the discriminating command, and only a not-read-only database means a real fault. RECORDED UNPROVEN: the retry loop is not exercised by any normal upgrade once 265's exemption lands — proof rides STATBUS-270's spec suite or deliberate fault injection (STATBUS-271). Refinement filed as STATBUS-272: with 265 in, a read-only refusal at the reset means the EXEMPTION did not take — the FATAL should lead with that, keeping deliberate-cases as the secondary branch.
<!-- SECTION:FINAL_SUMMARY:END -->
