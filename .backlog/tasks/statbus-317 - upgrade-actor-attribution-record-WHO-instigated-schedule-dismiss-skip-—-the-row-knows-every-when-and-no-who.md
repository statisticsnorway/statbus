---
id: STATBUS-317
title: >-
  upgrade-actor-attribution: record WHO instigated schedule/dismiss/skip — the
  row knows every when and no who
status: To Do
assignee:
  - architect
created_date: '2026-08-29 19:53'
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
