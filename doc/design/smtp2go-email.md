# SMTP2GO transactional email (send on user creation)

**Status:** deliverability layer live; application layer designed (this doc), not yet built.

**Provenance:** the original statbus app-layer design was lost to Claude Code
session reaping — which is why this now lives in git. **Part A** (deliverability)
is VERIFIED from the completed `statbus.org` DNS-restore work. **Part B** is the
DECIDED architecture, settled in a grounded review against statbus's actual
worker/DB model (2026-06-03). Markers: **VERIFIED** (true today), **DECIDED**
(agreed design), **TODO** (still to settle).

---

## Part A — Deliverability / sender infrastructure (VERIFIED, live)

SMTP2GO is the transactional relay for `statbus.org`. Sender domain verified;
MX is Domeneshop, outbound app mail is SMTP2GO. DNS on Domeneshop (authoritative
`ns1/2/3.hyp.net`), all phases complete.

| Type  | Host                 | Data                  | Purpose |
|-------|----------------------|-----------------------|---------|
| CNAME | `em599657`           | `return.smtp2go.net`  | Bounce / Return-Path subdomain |
| CNAME | `s599657._domainkey` | `dkim.smtp2go.net`    | DKIM signing — **required for DMARC alignment** |
| CNAME | `link`               | `track.smtp2go.net`   | Link/open tracking |
| TXT   | `@`                  | `v=spf1 include:_spf.domeneshop.no ~all` | SPF (MX is Domeneshop) |
| TXT   | `_dmarc`             | `v=DMARC1; p=reject; rua=mailto:dmarc@domeneshop.no` | DMARC, hard-fail |

DMARC `p=reject` works only because DKIM (`s599657._domainkey`) is published and
verified in the SMTP2GO dashboard: SPF authorizes Domeneshop (MX), DKIM authorizes
SMTP2GO (outbound), both align under DMARC. Validate live state against the
SMTP2GO dashboard and `dig … @ns1.hyp.net`. Part A is the canonical record.

---

## Part B — Application layer (DECIDED architecture)

### Flow
```
user_create  ──►  worker.tasks 'send_email'        ──►  email_outbox (queued) ──NOTIFY──►  worker-process sender fiber
(stops          (PL/pgSQL handler: RENDER from           (rendered row, state)               (HTTP POST → SMTP2GO,
 returning       email_template, mint setup-link                                              key in process env;
 password)       token from auth.secrets, INSERT                                              marks sent|failed + msg_id)
                 email_outbox, NOTIFY)                                                                │
                                                                                                      ▼
SMTP2GO events ──webhook──► PostgREST RPC ──► email_event ──► update email_outbox.state (delivered|bounced|spam)
```

### Why this shape (DECIDED)
- **Send runs in the worker process, not the DB.** The PL/pgSQL handler only
  *renders + enqueues*; a dedicated fiber in the worker process does the HTTP.
  Rationale (grounded in the pg_regress model — no worker process runs in tests,
  tasks are driven by `CALL worker.process_tasks()`):
  - **Testable:** render path is pure SQL → assert the queued `email_outbox` row
    and its rendered subject/body; **fake the send with
    `UPDATE email_outbox SET state='sent'`**. No network, no http stubbing.
  - Keeps outbound HTTP out of DB transactions, keeps the API key out of the DB,
    avoids a new Postgres egress surface. `pgsql-http` stays off.
- **`worker.tasks` orchestrates; `email_outbox` is the send buffer.** Reuses the
  existing task state machine, structured concurrency, and NOTIFY/LISTEN.

### Tables (TODO: build)
- **`email_template`** — PK `(template_key, locale)`; `subject`, `body_html`,
  `body_text`. Covers nb/en/ru/ky/ar; rendered at enqueue time. Editable without
  redeploy.
- **`email_outbox`** — `id`, `template_key`, `locale`, `recipient`,
  `payload jsonb` (render vars), `rendered_subject`, `rendered_html`, `state`
  (`queued|sending|sent|failed|bounced`), `attempts`, `smtp2go_message_id`,
  `claimed_at`, `last_error`, `created_at`, `sent_at`. UNIQUE idempotency key so a
  retried enqueue can't double-insert (AGENTS.md "always add constraints").
- **`email_event`** — `id`, `outbox_id` (fk), `smtp2go_message_id`,
  `event_type` (`delivered|bounce|spam|unsubscribe|…`), `payload jsonb`,
  `received_at`. Fed by the webhook; updates `email_outbox.state`.

### Components (DECIDED)
1. **Enqueue + render** — `worker.tasks` command `send_email`, PL/pgSQL handler
   registered in `worker.command_registry`: pulls `email_template` by
   `(template_key, locale)`, renders, mints a short-lived JWT setup-link token
   from `auth.secrets`, INSERTs `email_outbox` (`queued`), NOTIFY. `user_create`
   enqueues this and **no longer returns the password** (user sets it via the link).
   Two-tier validation: invalid email → fail-fast actionable error; valid-but-deferred → warn.
2. **Send (process fiber)** — a dedicated fiber in the worker process LISTENs,
   claims `queued` rows (`FOR UPDATE SKIP LOCKED`, `state→sending`, `claimed_at`),
   POSTs SMTP2GO's HTTP API (`SMTP2GO_API_KEY` + `EMAIL_FROM` in the process env,
   never the DB), writes back `sent`+`smtp2go_message_id` or `failed`+`last_error`.
   Crash-safe: an abandoned-reset returns stale `sending` rows to `queued` (mirror
   `worker_reset_abandoned_processing_tasks`). At-least-once; rare double-send on a
   crash between accept and mark — add an idempotency token if it matters.
3. **Inbound events** — SMTP2GO webhook → a PostgREST RPC (dedicated role +
   shared secret) inserts `email_event` and updates `email_outbox.state`
   (bounced/complained → flag the address). Real-time; matches the prefer-`/rest` model.
4. **Templates** — `email_template` DB table, per locale (above).

### Testability (DECIDED)
- Render: `CALL worker.process_tasks()` then assert `email_outbox` has the queued
  row with correct recipient + rendered content. Fake delivery with an `UPDATE`.
- Webhook: call the PostgREST RPC directly with a sample SMTP2GO payload; assert
  `email_event` insert + `email_outbox.state` transition.
- No network in any pg_regress test.

---

## Part C — Still to settle (TODO)
- Set-password route + token claims/TTL (uses `auth.secrets`).
- Idempotency token shape (skip double welcome on retry).
- Event scope beyond creation: recovery / email-change / invite (the
  `.env.example` `MAILER_URLPATHS_*` surface implies all four were once intended).
- Webhook auth: shared-secret header vs signature; which DB role the RPC runs as.
- SMTP2GO plan rate limits; whether link/open tracking is wanted per message.

## References (durable, in-repo)
- Auth hook: `doc/auth-design.md:455` — password-reset / token-via-email marked Future
- Enqueue point: `migrations/20240609000000_make_view_for_user_editing.up.sql:80` — `public.user_create`
- Worker model: `worker.command_registry` (`handler_procedure`), `worker.tasks`, `worker_reset_abandoned_processing_tasks`, `doc/worker-structured-concurrency.md`
- Config surface: `.env.example` → "Mailer Config" section

Part A records were recovered from the completed DNS-restore work (source note
outside the repo, may be gone). Parts A–C above are canonical.
