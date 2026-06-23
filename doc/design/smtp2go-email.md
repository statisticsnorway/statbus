# SMTP2GO transactional email (send on user creation)

**Status:** deliverability live; application layer designed + review-hardened; not yet built.

**Provenance:** the original app-layer design was lost to Claude Code session
reaping — which is why this lives in git. **Part A** (deliverability) is VERIFIED
from the completed `statbus.org` DNS-restore work. **Part B** is the DECIDED
architecture, then **hardened against an adversarial review (2026-06-23)** that
found the token / webhook / RLS security model load-bearing and under-specified;
those fixes (H1–H5, M1–M4) are folded in below. Markers: **VERIFIED** (true
today), **DECIDED** (agreed), **TODO** (still open).

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

DMARC `p=reject` works only because DKIM is published and verified in the SMTP2GO
dashboard. Validate live state against the dashboard and `dig … @ns1.hyp.net`.
Part A is the canonical record.

---

## Part B — Application layer (DECIDED, review-hardened)

### Flow
```
user_create ─► worker.tasks 'send_email' ─► email_outbox (queued) ─NOTIFY─► separate supervised sender loop
(email-only;    (PL/pgSQL handler: render +    (rendered row + state)          (claims FOR UPDATE SKIP LOCKED,
 stops          mint single-use token via                                       POSTs SMTP2GO HTTP, key in env,
 returning      SECURITY DEFINER, INSERT)                                        marks sent|failed + msg_id)
 password)                                                                              │
SMTP2GO events ─HMAC webhook─► SECURITY DEFINER RPC (low-priv role) ─► email_event ─► update email_outbox.state
```

### Security model (DECIDED — the load-bearing part, from review)
- **Setup-link token (H1/H2/H3).** statbus signs all JWTs with one shared
  `jwt_secret` and `auth.jwt_verify` checks only signature + `exp` — so scope is
  consumer-enforced, not cryptographic. Therefore the setup token MUST carry:
  `type='password_setup'` (a new type, never `'access'`), `role='anon'` (so it
  can't be replayed against `/rest` as a session), a short TTL (minutes), and a
  unique `jti`.
  - **Single-use:** mint also writes a row in **`auth.password_setup_token`**
    (`jti uuid PK`, `user_id fk`, `expires_at`, `consumed_at`) — mirrors the
    proven `auth.api_key` jti/revocation pattern. The set-password RPC verifies
    `jti` is unconsumed + unexpired, hard-checks **`type` AND `role`** (as
    `public.change_password` already does), then sets `consumed_at` in the same tx.
  - **Minting is the ONLY path touching `auth.secrets`** and MUST be a dedicated
    **`SECURITY DEFINER`** function — `user_create` is `SECURITY INVOKER` and the
    worker handler runs as the unprivileged `worker` role; `auth.secrets` is
    force-RLS / zero-policy, so a non-DEFINER mint throws at runtime.
- **Webhook ingest (H4).** Verify the **SMTP2GO HMAC signature inside a
  `SECURITY DEFINER` RPC** granted only to a **dedicated low-privilege role**
  (today an unauthenticated POST runs as `anon`; a shared-secret header is weak).
  Reject on signature mismatch; require `smtp2go_message_id` to map to an existing
  `email_outbox` row before any state change. (Blocks forged bounce → address-flag
  → account-creation DoS.)
- **RLS / PII (H5).** RLS ON for `email_outbox`, `email_event`, `email_template`.
  **No `authenticated` / `regular_user` SELECT** — these hold recipient PII and
  bodies containing the live setup token. Access only via the DEFINER
  mint/send/webhook functions; admin-only read at most. Drop/redact
  `rendered_html` once `state='sent'`.

### Tables (DECIDED; to build) — all RLS-ON, DEFINER-only access
- **`email_template`** — PK `(template_key, locale)`; `subject`, `body_html`, `body_text`.
- **`email_outbox`** — `id`, `template_key`, `locale`, `recipient`, `payload jsonb`,
  `rendered_subject`, `rendered_html` (redacted after sent), `state`
  (`queued|sending|sent|failed|bounced|complained|suppressed`), `attempts`,
  `smtp2go_message_id` **UNIQUE** (event linkage, L1), `claimed_at`, `last_error`,
  `created_at`, `sent_at`. **Idempotency (M4):** UNIQUE `(template_key, recipient, dedupe_key)`
  — `dedupe_key` = originating `user_id` for welcome-on-create.
- **`email_event`** — `id`, `outbox_id fk` (nullable; an event can arrive before
  send is marked — reconcile via `smtp2go_message_id`, L1), `smtp2go_message_id`,
  `event_type` (`delivered|bounce|spam|complained|unsubscribe|…`), `payload jsonb`,
  `received_at`.

### Components (DECIDED)
1. **Enqueue + render** — `worker.tasks` command `send_email`, PL/pgSQL
   `handler_procedure` (signature `(payload jsonb, info jsonb)` per
   `worker.process_tasks`): renders from `email_template`, calls the DEFINER mint
   (token + `password_setup_token` row), INSERTs `email_outbox` (`queued`), NOTIFY.
   `user_create` enqueues and **stops returning the password**. Two-tier
   validation (L3): unparseable email → hard error, **no user row**; well-formed
   but unverified → create user + enqueue + soft status (never silent).
2. **Send — separate supervised loop (M1).** `cli/src/worker.cr` is a generic
   schema-driven dispatcher with **no per-command hook**, so the sender is a
   **NEW, separately-supervised loop with its own lifecycle** (startup, graceful
   shutdown, advisory lock, abandoned-reset) — **NOT** under the worker.tasks
   structured-concurrency tree (don't claim reuse it can't provide). It
   LISTENs/polls `email_outbox`, claims `FOR UPDATE SKIP LOCKED`
   (`state→sending`, `claimed_at`), POSTs the SMTP2GO HTTP API
   (`SMTP2GO_API_KEY` + `EMAIL_FROM` in process env, never the DB), writes back
   `sent` + `smtp2go_message_id` or `failed` + `last_error`.
3. **Crash-safety (M2).** A **dedicated** outbox reset — NOT
   `worker_reset_abandoned_processing_tasks` (it only touches `worker.tasks` and
   resets to `interrupted`) — returns stale `sending` rows (`claimed_at` older
   than N) to `queued`; runs at sender startup + periodically. At-least-once: a
   crash after SMTP2GO accepts but before the mark can double-send; the
   idempotency key / `smtp2go_message_id` is the backstop.
4. **Events** — SMTP2GO webhook → the DEFINER RPC (above) inserts `email_event`
   and updates `email_outbox.state` (`bounced`/`complained` → suppress address).
5. **Templates** — `email_template` DB table, per locale.

### Testability (DECIDED)
- Render is SQL-testable: `CALL worker.process_tasks()`, assert the queued
  `email_outbox` row + rendered content (the mint is DEFINER-callable in-tx).
- Fake delivery with `UPDATE email_outbox SET state='sent'`. The sender loop does
  not run under pg_regress → **no network in tests**.
- Webhook RPC testable by direct call with a signed sample payload.

---

## Part C — remaining TODO
- **M3 — locale source.** statbus has **no** per-user/instance locale today (no
  `user.locale`, no `settings` locale column, no DB locale enum). Decide: add
  `user.locale`, an instance default in `settings`, or capture at `user_create`;
  define a fallback. Blocks populating `email_outbox.locale`.
- Template body content per locale + the set-password route/page.
- Exact SMTP2GO HMAC scheme + the dedicated webhook role definition.
- SMTP2GO plan rate limits; per-message link/open tracking.
- Event scope beyond creation (recovery / email-change / invite — the
  `.env.example` `MAILER_URLPATHS_*` surface implies all four).

## References (durable, in-repo)
- Auth/JWT/secrets/revocation: `doc/auth-design.md`; `auth.api_key` (jti + revoked_at), `auth.jwt_verify`, `auth.secrets` (force-RLS), `public.change_password` (type-check precedent)
- Enqueue point: `migrations/20240609000000_make_view_for_user_editing.up.sql` — `public.user_create` (SECURITY INVOKER, currently returns the password)
- Worker model: `worker.command_registry` (`handler_procedure`), `worker.tasks`, `worker.process_tasks`, `worker_reset_abandoned_processing_tasks`, `doc/worker-structured-concurrency.md`; `cli/src/worker.cr` (generic dispatcher — no per-command hook)
- Config surface: `.env.example` → "Mailer Config"

**Review note:** hardened per adversarial review 2026-06-23 — H1–H5 (token
scope / single-use / DEFINER mint / webhook HMAC / RLS) folded as DECIDED; M1
(sender separately supervised), M2 (dedicated outbox reset), M4 (idempotency key)
folded; M3 (locale source) + content remain TODO. Parts A–C above are canonical.
