---
id: STATBUS-173
title: >-
  standalone-pgadmin: local pgAdmin on the standalone host at /pgadmin, JWT/user
  model resolved (no superadmin)
status: To Do
assignee: []
created_date: '2026-07-13 11:39'
labels:
  - standalone
  - tooling
  - not-install-upgrade
dependencies: []
priority: low
ordinal: 174000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
> NORTH STAR: a standalone host (e.g. no.statbus.org) serves its own local pgAdmin at a path (no.statbus.org/pgadmin) for operator DB inspection, WITHOUT weakening the auth model — pgAdmin does not run as superadmin and does not hold its own separate credentials.
> ORIGIN: captured from the feature/pgadmin branch (King, 2026-07-13, during the STATBUS-035 branch walk) so the branch's intent lives in a ticket and the branch can be retired. The branch has a working-ish prototype (multi-tenant pgAdmin compose + custom image with an SSLSNI patch + a command-palette link + forward_auth handling); it is a starting reference, not the design.
> STAGE: standalone / ops tooling — post the current release train.
> COMPLEXITY: engineer-substantial — the hard part is NOT deploying pgAdmin, it is the auth model.

THE OPEN DESIGN PROBLEM (the reason this is a real ticket, not a copy-the-branch): pgAdmin's own auth vs statbus's. Two sub-questions to resolve:
1. JWT HANDLING — can pgAdmin accept/derive identity from the app's own JWT (the token the statbus app already issues), so an operator authenticated to statbus reaches pgAdmin without a second credential? Or is a bridge needed (Caddy forward_auth validating the statbus JWT before proxying to pgAdmin at /pgadmin)?
2. THE DB ROLE pgAdmin CONNECTS AS — explicitly NOT superadmin. What role does pgAdmin use to talk to Postgres, and how is it scoped (read-mostly inspection role? the operator's own mapped role via the JWT→role mechanism statbus already has)? Users-in-pgAdmin vs users-in-statbus must not fork into a second identity store.

REFERENCE (feature/pgadmin branch, tip 7b01c88... — actually the pgadmin tip; retire after this ticket exists): multi-tenant deployment config, custom pgAdmin image with SSLSNI patch, forward_auth handle_response for the unauthorized redirect, DEPLOYMENT.md doc, command-palette link. Mine it for the deployment mechanics; the auth model is the design work.

CONSTRAINT: standalone-only initially (no.statbus.org shape); the multi-tenant cloud case is a later question. Path-based (/pgadmin), not a subdomain, per the King's framing.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Auth model ruled: how an operator authenticated to statbus reaches /pgadmin without a second credential (app-JWT reuse vs a forward_auth bridge), documented before build
- [ ] #2 pgAdmin connects to Postgres as a scoped role that is NOT superadmin; the role and its grants are named and justified
- [ ] #3 No second identity store: pgAdmin users are not a separate user list from statbus's — the mapping is explicit
- [ ] #4 no.statbus.org/pgadmin serves pgAdmin path-based on the standalone host, proven on a real box (rune-no or a test standalone)
- [ ] #5 The feature/pgadmin branch's reusable deployment mechanics are mined into the shipped form; the branch is then retired
<!-- AC:END -->
