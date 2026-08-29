---
id: STATBUS-317
title: >-
  upgrade-actor-attribution: record WHO instigated schedule/dismiss/skip — the
  row knows every when and no who
status: In Progress
assignee:
  - mechanic
created_date: '2026-08-29 19:53'
updated_date: '2026-08-29 20:11'
labels:
  - upgrade
  - ops
  - app
dependencies: []
priority: medium
type: enhancement
ordinal: 310000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
NORTH STAR: an NSO's production upgrade history answers "who did this?" — today it cannot. Found live on 2026-08-29: Norway's rc.17 install was driven by one of two people, and neither the UI nor the database can say which; even the account owner could not tell.

THE GAP, verified from the schema (doc/db/table/public_upgrade.md): public.upgrade records scheduled_at/started_at/completed_at/dismissed_at/skipped_at — every WHEN, no WHO. Mechanically the CLI cannot know today: operators act as the box's shared unix user (statbus@rune, statbus_<slot>@niue), so personal identity is erased at the SSH layer.

DESIGN QUESTIONS (architect): (1) the column(s) — e.g. scheduled_by/dismissed_by/skipped_by text, nullable for the automatic paths (service-driven actions attribute to 'upgrade-service'); (2) the CLI's identity source — best-effort capture (SSH_CLIENT/SSH_AUTH info, or the key comment/fingerprint from the authorized_keys match) vs an explicit --operator flag vs an interactive prompt at schedule time (the deliberate act deserves a deliberate name); (3) if the admin UI ever gains schedule/dismiss buttons, the authenticated statbus user attributes for free — the API path should carry it from day one; (4) honesty rule: never fabricate an actor — absent identity is recorded as absent, loudly, not defaulted.

FRAME: African statistical offices run this in production; audit attribution of production-changing actions is baseline expectation, not a nicety.

WHAT IS ACHIEVED: the upgrade page can show "scheduled by X", and the question the King could not answer on 2026-08-29 becomes answerable forever.
<!-- SECTION:DESCRIPTION:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
**Architect design (2026-08-29 night), REPLACING the ticket's proposed column shape:** attribution belongs on the EXISTING public.upgrade_state_log — it already records every transition with application_name/query/backend_pid; only human identity is missing. Three scheduled_by-style columns on public.upgrade would duplicate the log and need a fourth column for a fourth action. MECHANISM: the trigger that populates the log resolves `actor` + `actor_source` in precedence order — auth.uid() ('verified') → session GUC statbus.actor set by the CLI via transactional set_config ('self-reported') → NULL ('absent'). Record how you know, not just who: a verified UI user and a typed string must never be indistinguishable. Automatic paths need NO work (application_name already distinguishes the service; no 'upgrade-service' magic value). The API/UI path comes FREE via auth.uid(). CLI: --operator flag primary; prompt ONLY on TTY-present + flag-absent. TWO NAMED TRAPS: a naive prompt wedges the non-interactive CI deploy door (hangs the automatic canary); set_config(...,true) outside a transaction is a silent no-op — the CLI must wrap set-then-write in one transaction and the test must prove the value LANDS. rc.18 slice: migration + trigger + CLI flag/prompt + upgrade-list display; NO backfill ever (absent is the true historical value). Implementer: mechanic, tonight.
<!-- SECTION:NOTES:END -->
