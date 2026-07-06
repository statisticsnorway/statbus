---
id: STATBUS-105
title: 'smtp2go-email: transactional email — send on user creation'
status: To Do
assignee: []
created_date: '2026-06-23 11:53'
labels:
  - email
  - auth
  - worker
  - security
dependencies: []
documentation:
  - doc/design/smtp2go-email.md
ordinal: 105000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
DB-centric transactional email via SMTP2GO: when a user is created, email them a single-use password-setup link instead of returning the password to the admin caller.

Design is committed and review-hardened — see `doc/design/smtp2go-email.md` (master `ca0a3c603`, hardened 2026-06-23). Deliverability (DNS/DKIM/DMARC) is already live. The app layer is DECIDED: `user_create` → `worker.tasks` `send_email` (PL/pgSQL renders from `email_template`, mints a single-use token via a SECURITY DEFINER fn, inserts `email_outbox`, NOTIFY) → a separately-supervised sender loop POSTs the SMTP2GO HTTP API (key in process env) → SMTP2GO events ingested via an HMAC-verified DEFINER webhook RPC into `email_event`.

This is the TRACKING ANCHOR for the feature; at execution it should be split into subtasks (schema+RLS, worker command+render, sender loop, webhook RPC, user_create change, set-password route, templates). An adversarial review found the security model load-bearing — the acceptance criteria below are the gates that must hold before this ships. Build is also gated on resolving the locale source (M3): statbus has no per-user/instance locale today.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Setup-link token is scoped and single-use: claims type='password_setup' (never 'access') + role='anon' + short TTL + unique jti, consumed via a new auth.password_setup_token table; a captured link cannot be replayed as an access token against /rest
- [ ] #2 Token minting is the ONLY code path reading auth.secrets and is a dedicated SECURITY DEFINER function (worker role + user_create INVOKER context cannot otherwise read force-RLS auth.secrets)
- [ ] #3 SMTP2GO webhook ingest verifies the HMAC signature inside a SECURITY DEFINER RPC granted only to a dedicated low-privilege role; a forged POST cannot insert arbitrary email_event rows or flip email_outbox.state
- [ ] #4 email_outbox, email_event, and email_template have RLS ON with no authenticated/regular_user SELECT; rendered bodies containing the live token are not readable and are redacted/dropped after state='sent'
- [ ] #5 Sending runs in a separately-supervised sender loop (documented as NOT part of worker.tasks structured concurrency); a crash leaves a resumable state via claim (FOR UPDATE SKIP LOCKED) + a dedicated outbox reset of stale 'sending' rows
- [ ] #6 user_create stops returning the password; an unparseable email is a hard error (no user row), a well-formed-but-unverified email is a soft status (never silent)
- [ ] #7 Render path is pg_regress-testable with zero network (sender loop absent in tests); delivery is fakeable via UPDATE email_outbox SET state='sent'
- [ ] #8 Locale source for email bodies is decided and implemented (M3) — statbus currently has no user.locale or settings locale
- [ ] #9 Tests and documentation are included in this work (not deferred)
<!-- AC:END -->
