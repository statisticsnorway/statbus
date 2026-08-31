---
id: STATBUS-332
title: >-
  config-apply-gap: every .env.config key needs regenerate-and-restart to take
  effect, and only the channel has a command that does it
status: To Do
assignee: []
created_date: '2026-08-31 14:56'
updated_date: '2026-08-31 14:58'
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
- [ ] #1 ./sb install (nothing-scheduled path) applies .env.config changes: regenerates outputs and restarts what the change requires (design question resolved: unconditional vs detect-what-changed)
- [ ] #2 The upgrade-channel verb is removed in the same landing, with a doc sweep
- [ ] #3 No second config-application mechanism: the step-table is the one home
- [ ] #4 Composes with install's existing step table and its flag/flock mutex without a second protected region
<!-- AC:END -->

## Comments

<!-- COMMENTS:BEGIN -->
author: foreman
created: 2026-08-31 14:58
---
Foreman (2026-08-31): consolidated — this ticket and STATBUS-331 were filed independently within minutes for the same gap (foreman from the architect's ruling; engineer at the architect's instruction). This entry has the fuller reasoning and stands; 331's acceptance criteria folded in above; 331 archived as duplicate.
---
<!-- COMMENTS:END -->
