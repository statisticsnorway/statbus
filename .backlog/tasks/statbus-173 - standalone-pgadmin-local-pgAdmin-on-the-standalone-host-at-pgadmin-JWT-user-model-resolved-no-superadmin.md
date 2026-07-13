---
id: STATBUS-173
title: >-
  standalone-pgadmin: local pgAdmin on the standalone host at /pgadmin, JWT/user
  model resolved (no superadmin)
status: To Do
assignee: []
created_date: '2026-07-13 11:39'
updated_date: '2026-07-13 15:28'
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
- [x] #1 Auth model ruled: how an operator authenticated to statbus reaches /pgadmin without a second credential (app-JWT reuse vs a forward_auth bridge), documented before build
- [ ] #2 pgAdmin connects to Postgres as a scoped role that is NOT superadmin; the role and its grants are named and justified
- [ ] #3 No second identity store: pgAdmin users are not a separate user list from statbus's — the mapping is explicit
- [ ] #4 no.statbus.org/pgadmin serves pgAdmin path-based on the standalone host, proven on a real box (rune-no or a test standalone)
- [ ] #5 BUILDS ON the feature/pgadmin branch (King, 2026-07-13): the branch is the working foundation — rebase/port its deployment mechanics forward (multi-tenant compose, custom pgAdmin image + SSLSNI patch, forward_auth handle_response, command-palette link, DEPLOYMENT.md doc) and resolve the auth model on top. The branch is KEPT, not retired, until this ships.
<!-- AC:END -->

## Comments

<!-- COMMENTS:BEGIN -->
author: foreman
created: 2026-07-13 11:55
---
SCOPE CORRECTION (King, 2026-07-13): this ticket BUILDS ON feature/pgadmin — the branch is the foundation, not a reference to retire. Rebase/port its deployment mechanics forward and resolve the auth model on top. feature/pgadmin is KEPT (removed from the STATBUS-035 delete-candidates) until this ships.
---

author: architect
created: 2026-07-13 15:28
---
AUTH MODEL RULED (architect, 2026-07-13) — grounded in the branch's actual content (auth_gate migration + servers.json read) and the auth schema (auth.user's sync_user_credentials_and_roles_trigger / drop_user_role_trigger, doc/db auth_user.md). The decisive existing fact: statbus users ALREADY have per-user PostgreSQL roles with synchronized credentials — the operator's statbus email+password IS a loginable PG identity carrying their statbus_role membership and RLS. The design is therefore an ASSEMBLY of existing machinery, not new auth:

(1) PERIMETER — the forward_auth bridge, NOT app-JWT consumption by pgAdmin. pgAdmin (Flask, its own session model) cannot and should not consume our JWT natively — that would fork session semantics. The branch's own `public.auth_gate()` pattern is RATIFIED as the shape: Caddy forward_auth → PostgREST /rest/rpc/auth_gate → validates the statbus access-token COOKIE (SECURITY DEFINER, auth.jwt_verify) → 200 with the user's email in a response header / 401 with handle_response redirecting to statbus login. Reaching /pgadmin requires live statbus authentication; no second web credential exists. INSIDE the perimeter, pgAdmin runs WEBSERVER AUTH (AUTHENTICATION_SOURCES=['webserver'] + auto-create-user): it trusts the email header Caddy forwards from auth_gate — which the branch's gate already emits for exactly this — so pgAdmin's internal user record is DERIVED from statbus identity (a profile row keyed on the same email, holding NO password). One wiring rule: Caddy must strip/overwrite any client-supplied copy of that header before setting it — the header is an internal assertion, never client input.

(2) THE DB ROLE — the operator's OWN synced PG role, entered at the pgAdmin server connection (the branch's servers.json shape: Username empty, the operator types their statbus email + password). Justified: the sync triggers already maintain these roles; RLS and statbus_role membership (regular_user/admin_user) apply exactly as they do through PostgREST — pgAdmin becomes just another PG client of the SAME identity, with the same visibility the operator already has. Explicitly REJECTED: superadmin/postgres (obvious), AND a shared read-only inspection role — a shared role blurs per-user audit attribution and bypasses the per-user RLS model we already paid for. Nothing weaker than the app's own model, nothing stronger than the operator's own rights.

(3) NO SECOND IDENTITY STORE, enforced by two settings: identity + credentials live ONLY in auth.user + the synced PG roles; pgAdmin's internal table holds auto-created email-keyed profile rows with no passwords (webserver auth), and PASSWORD SAVING IS DISABLED (PGADMIN_CONFIG_ALLOW_SAVE_PASSWORD=False) so pgAdmin's sqlite can never accumulate PG credentials — the operator enters their password per session, same as psql. The mapping statbus-user ↔ pgAdmin-profile ↔ PG-role is one email, three views of one identity.

MINED FROM THE BRANCH as deployment mechanics (not design): the custom image + SSLSNI patch, the compose shape (standalone subset — the multi-tenant servers.cloud.json is out of scope per the ticket), the handle_response redirect, the command-palette link. BUILD NOTES: the auth_gate migration needs re-porting against the CURRENT auth schema (it predates months of auth work — verify jwt_verify/extract_access_token signatures); AC#4's real-box proof on a standalone is the oracle. AC#2/#3's answers are contained above; they check when built and proven.
---
<!-- COMMENTS:END -->
