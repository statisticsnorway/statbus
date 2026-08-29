---
id: STATBUS-319
title: >-
  policy-symmetry-guard: every role with a write policy on public.upgrade must
  hold the matching upgrade_state_log INSERT policy — assert it in a catalog
  test
status: To Do
assignee: []
created_date: '2026-08-29 20:45'
labels:
  - upgrade
  - testing
dependencies: []
priority: low
type: enhancement
ordinal: 312000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
NORTH STAR: the symmetry that made 317's INVOKER trigger safe stays true by assertion, not by memory. Today it is a current fact (architect-verified 2026-08-29: superusers bypass RLS on both tables; admin_user holds the one write policy on each — and even a postgres-owned DEFINER writer runs as postgres, whose rolbypassrls covers the log too). If someone later adds a write-permitting policy on public.upgrade for a new role WITHOUT the matching upgrade_state_log INSERT policy, the log trigger fails for that role — and it fails the ENTIRE transition, not just the logging.

THE GUARD: a pg_regress catalog test reading pg_policy and asserting the symmetry — every role named in a write-permitting (INSERT/UPDATE/DELETE/ALL) policy on public.upgrade appears in a write-permitting policy on public.upgrade_state_log. Failure text names the missing policy and this ticket.

WHY THIS IS A FOLLOW-UP AND NOT PART OF 317 (architect's explicit ruling, recorded so nobody re-litigates the urgency): the failure this guards is LOUD — the transition fails outright and announces itself — unlike the silent classes that drove the week's blocking guards. A visible break gets fixed the day it happens; the guard just makes the diagnosis instant.

WHAT IS ACHIEVED: the day someone widens who may write upgrades, the test tells them the log must widen with it — before their transition mysteriously fails.
<!-- SECTION:DESCRIPTION:END -->
