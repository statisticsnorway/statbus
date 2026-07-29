---
id: STATBUS-142
title: 'smtp2go-email: transactional email — send on user creation'
status: To Do
assignee: []
created_date: '2026-06-23 11:53'
updated_date: '2026-07-29 11:15'
labels:
  - email
  - auth
  - worker
  - security
dependencies: []
documentation:
  - doc/design/smtp2go-email.md
ordinal: 143000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
> NORTH STAR: a newly created user receives their credentials/welcome by email — no operator copy-pasting secrets over side channels.
> STAGE: design DONE and review-hardened; implementation not started. Build follows doc/design/smtp2go-email.md — the authoritative design — not a fresh sketch. One sequencing decision below.

WHERE THIS ACTUALLY STANDS (corrected 2026-07-29 — the operator's code sweep confirmed no implementation exists, but the DESIGN is far from greenfield):
- PART A, VERIFIED LIVE: SMTP2GO is the transactional relay for statbus.org — sender domain verified, DKIM/SPF/DMARC(p=reject) published and validated, DNS complete. Nothing to build here; re-validate against the SMTP2GO dashboard + dig at build time per the doc.
- PART B, DECIDED + HARDENED, NOT BUILT: the application-layer architecture is designed and was hardened against an adversarial review (2026-06-23) — the token/webhook/RLS security model fixes (H1–H5, M1–M4) are folded into the doc. The doc marks each item VERIFIED / DECIDED / TODO.
- CODE, GREENFIELD (operator-verified): no SMTP config keys, no email client, no notification machinery in the repo; user creation (CLI `./sb users create` + the web path) has no hook. The worker task queue (worker.tasks) is the ready dispatch substrate.

THE BUILD = implement Part B as the doc specifies, including every H/M hardening — the doc supersedes any sketch, including earlier versions of this ticket.

THE ONE SEQUENCING DECISION (open — decide at prioritization, AC#4): the worker is Crystal today; STATBUS-093 (the Go worker port) replaces it. Implementing the email task in Crystal means porting it again under 093; landing it as 093's first new task class means 142 waits on 093. Decide when either is prioritized — never build the two in ignorance of each other.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Part B built exactly per doc/design/smtp2go-email.md including every H1–H5 / M1–M4 hardening — any deviation is a doc update first, reviewed
- [ ] #2 Part A deliverability re-validated at build time against the SMTP2GO dashboard + dig per the doc's live-state check
- [ ] #3 User creation (CLI and web, one shared hook per the doc's model) enqueues the email through the worker task queue; permanent failure is a visible task state, never silence
- [ ] #4 The 093 sequencing decision is recorded before build: ride the current worker or land as the Go worker's first new task class
<!-- AC:END -->
