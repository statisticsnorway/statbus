---
id: STATBUS-185
title: >-
  silent-failfast-gaps: three silently-ignored errors found by the lint
  burn-down (jwt reload, linger, env backup)
status: To Do
assignee: []
created_date: '2026-07-14 18:40'
labels:
  - fail-fast
  - defect
  - cli
dependencies: []
priority: medium
ordinal: 186000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
> NORTH STAR: fail-fast — a failed step the operator depends on is never silent. Three call sites ignore errors whose failure leaves the box in a wrong or unprotected state with zero signal. Found by the STATBUS-176 errcheck burn-down (2026-07-14, mechanic); left as minimal explicit-ignores in the burn-down per the no-silent-behavior-change rule; each needs a deliberate reviewed fix.

1. cmd/db.go — recreate-database's JWT-secret reload (jwtCmd.Run()) ignores failure. Consequence: a restored/recreated DB serves with the WRONG jwt_secret — an auth outage with no operator-visible signal. Highest severity of the three.
2. cmd/install.go — `loginctl enable-linger` ignores failure. Consequence: the user's systemd units do not survive logout; on a standalone NSO box that means the upgrade daemon dies when the operator's session ends, silently.
3. internal/config/config.go — the pre-overwrite .env backup write ignores failure. Consequence: config regenerate proceeds with no recovery copy of the previous .env.

FIX SHAPE (per site, engineer judgment + review): surface the error — hard-fail where the subsequent state is wrong (1), loud warning with remedy where degraded-but-operable (2, 3 debatable). Each is a small change in operator-facing flows; review chain applies.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Each of the three sites either hard-fails or warns loudly with a named remedy — ruled per site, none stays silent
- [ ] #2 The explicit-ignore markers from the 176 burn-down at these sites are replaced by the ruled handling
<!-- AC:END -->
