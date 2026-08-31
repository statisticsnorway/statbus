---
id: STATBUS-332
title: >-
  config-apply-gap: every .env.config key needs regenerate-and-restart to take
  effect, and only the channel has a command that does it
status: Done
assignee:
  - '@mechanic'
created_date: '2026-08-31 14:56'
updated_date: '2026-08-31 21:43'
labels:
  - cli
  - config
  - ops
dependencies: []
priority: medium
type: enhancement
ordinal: 325000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
NORTH STAR: editing a setting is the whole act. An operator who changes something in .env.config should not also have to know which two commands make it real, and the product should not have solved that for exactly one key.

THE GAP (architect, 2026-08-31, filed out of STATBUS-307 at his instruction — deliberately NOT folded into that landing): a value in .env.config does nothing observable until `./sb config generate` rewrites .env AND the affected service restarts. The upgrade daemon in particular loads its config only at startup, which is why doc/CLOUD.md tells the reader to confirm the channel by reading the RUNNING service rather than the file — a file that says `stable` proves nothing until a restart has happened.

This is GENERAL, not channel-specific. A port change, a credential rotation, a SITE_DOMAIN change, a backup-interval change all have it. The failure mode is identical every time and is this project's recurring one: the file says one thing and the box does another, with a grep of the file falsely confirming success.

WHAT 307 LEFT BEHIND, and why it is a half-answer worth finishing rather than a wart to remove: `./sb upgrade channel` writes the key, regenerates, and restarts — the whole act, for one key. The architect's ruling on it went REMOVE and then reversed to KEEP after reading the function, precisely because that third step is real work an operator would otherwise carry in their head. So the verb is right and its scope is wrong: it solves one Nth of the problem, and is the only key that gets a solution.

THE RIGHT HOME (architect): `./sb install` — the single entrypoint an NSO operator already knows, which is idempotent by construction and already owns applying derived config. If install applied .env.config changes as part of its ordinary work, then editing the file and running the one command an operator already runs would be the whole act for EVERY key.

WHAT FOLLOWS FOR THE VERB: once install does this, `./sb upgrade channel` becomes redundant and can be removed for the reason originally given — the channel should be visible on the line where someone chose it, and a verb that writes it from elsewhere weakens that. It stays until then because removing it now would relocate real work into the operator's memory.

DESIGN QUESTIONS: which services need a restart for which keys (the upgrade daemon certainly; Caddy on domain/port changes; the app on others), whether install should restart unconditionally or detect what actually changed, and how this composes with install's existing step table and its mutex.

WHAT IS ACHIEVED: one command applies any configuration change, no key is privileged with its own verb, and the file-says-one-thing-box-does-another failure stops being reachable by editing a setting.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 ./sb install (nothing-scheduled path) applies .env.config changes: regenerates outputs and restarts what the change requires (design question resolved: unconditional vs detect-what-changed)
- [x] #2 The upgrade-channel verb is removed in the same landing, with a doc sweep
- [x] #3 No second config-application mechanism: the step-table is the one home
- [x] #4 Composes with install's existing step table and its flag/flock mutex without a second protected region
<!-- AC:END -->

## Comments

<!-- COMMENTS:BEGIN -->
author: foreman
created: 2026-08-31 14:58
---
Foreman (2026-08-31): consolidated — this ticket and STATBUS-331 were filed independently within minutes for the same gap (foreman from the architect's ruling; engineer at the architect's instruction). This entry has the fuller reasoning and stands; 331's acceptance criteria folded in above; 331 archived as duplicate.
---

author: architect
created: 2026-08-31 19:46
---
**BUILDABLE DESIGN.**

**Purpose, in two sentences.** A configuration change should take effect when the operator applies it, not when someone remembers which services cache it. `./sb install` becomes the one command that makes `.env.config` true of the running box.

## RULING: detect-what-changed, NOT unconditional restart

Simpler normally wins. **Here it is wrong, for a reason that comes straight from the deployment frame:** `./sb install` is the command an NSO operator is told to run freely — *if something is broken, run it again*. **An unconditional restart makes that advice cost downtime every single time**, and the safe-to-run-anytime property is exactly what makes install viable as the one entrypoint. Losing it to save a diff is a bad trade.

## The map lives AT THE KEY, not in a parallel table

Each generated key declares its **restart class** at the site where it is generated. Classes: `none`, `caddy-reload`, `app`, `rest`, `db`, `upgrade-daemon`.

**Not a separate key→service list**, because such a list restates knowledge the generator already has, and two records drift. **The drift here is silent in the worst direction:** someone adds a key, forgets the table, and that key's changes never take effect — a config that looks applied and is not.

*Builder check:* confirm against compose which services actually consume which vars. **If compose shares one `env_file` across services, the class is a product decision rather than a compose fact** — which is a further reason to declare it at the generator rather than derive it.

## Detection: diff the GENERATED `.env`, never `.env.config`

Capture the generated `.env` before regeneration, diff keys after, union the restart classes of the changed keys, act once.

**It must be the generated file, and this is a direct consequence of STATBUS-307:** the channel now derives **live** from the mode, so changing `CADDY_DEPLOYMENT_MODE` moves `UPGRADE_CHANNEL` in `.env` **while `.env.config` carries no channel at all**. **Diffing `.env.config` would miss exactly the change 307 introduced.**

## Composition: one protected region, not two

The apply step is **a step in install's existing step table**, running after `config generate`, **inside the flag/flock region install already acquires** — per the STATBUS-323 ruling. No second acquire; a second one would `EWOULDBLOCK` against the process's own hold.

## The channel verb is removed by this

Once install applies config, the verb's three steps (write, generate, restart) are precisely what install does, and the sequence becomes **edit `.env.config` → `./sb install`** — which is already how `CADDY_DEPLOYMENT_MODE` is configured, restoring the symmetry the two-variable model wants.

**Recorded honestly: this is the moment my original removal ruling becomes correct.** It was wrong when I first gave it, because the verb was then the only thing performing generate-and-restart; removing it would have moved that sequence into the operator's memory. **332 supplies the general mechanism, and only then does the special-case verb become redundant.** Remove it here, with the docs, in this landing.

## Acceptance criteria

1. Changing a key of restart class X and running install restarts **exactly** X — proven per class, not in aggregate.
2. **Changing nothing and running install restarts nothing.** This is the safe-to-run-anytime property; it gets its own test.
3. A mode change that moves the derived channel **is detected**, proving the diff is over the generated `.env`.
4. Every generated key carries a restart class; **a new key without one fails a test** (derived enumeration over the generator, not a hand list).
5. The apply step runs inside install's existing protected region — no second acquire.
6. The channel verb is removed and its doc mentions updated in the same landing.
7. **Red-verified: making the apply unconditional fails the no-change-no-restart test.**

## What is achieved

An operator edits one file and runs one command, and the running box matches what they wrote — with no service restarted that did not need to be, so the command stays safe to run whenever they are unsure.
---
<!-- COMMENTS:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
LANDED at 9fead5e3c (architect hands-on approve + foreman landing review incl. the AST pin; full suite green across 17 packages). ./sb install now applies .env.config changes: snapshot before the step loop, diff of the GENERATED .env after the Generated-env step (the 307 rule — derived keys live only there), restarts of exactly what changed via an "Apply config changes" step, no-change runs restart nothing (test-pinned both directions). DECLARATION SHAPE: every key declares its restart-class SET at its own write site (classes.declare adjacent to the write; empty-set = explicitly none); SEVEN classes — worker got its own (the architect: folding it under app either over-restarts, losing the minimal-restart property, or silently misses — either failure costs the design) and proxy-restart is named for its real cost (reuses cert.go's docker compose restart proxy; a graceful reload later should rename the constant because the cost changes with it). SECOND SIGNAL, architect-ratified as the design's own rule applied to a second consumer: caddy/config/*.caddyfile content diffed directly (templates and cert files never reach .env), file list from config.CaddyConfigFiles kept honest by its own test; a READ FAILURE folds into the snapshot (with UnixNano so a stable error can never compare equal) — failure-to-observe is never evidence of no-change. THREE STRUCTURAL PINS, all red-verified: TestNoStepAfterApplyConfigChangesRegeneratesEnv (the last-writer property, AST-bounded per-step); TestGenerateEnvContent_EveryKeyHasARestartClass; TestBatchClassifiedKeysHaveZeroComposeConsumers (the batch's actual claim, scoped by the exact-[RestartNone] signature to respect the mechanic's read-fresh distinction — keys whose consumers dotenv.Load at point of need are legitimately no-restart with live consumers). THE CHANNEL VERB REMOVED (upgradeChannelCmd + registration; ValidateChannel unexported) — completing the architect's ruled sequence: with install applying config changes generally, the special case is redundant, which is when his original removal reasoning became correct. ops/statbus-upgrade.service drift comment repointed to the real remaining second formatter.
<!-- SECTION:FINAL_SUMMARY:END -->
