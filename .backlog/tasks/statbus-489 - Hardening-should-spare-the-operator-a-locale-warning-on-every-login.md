---
id: STATBUS-489
title: Hardening should spare the operator a locale warning on every login
status: To Do
assignee: []
created_date: '2026-10-13 12:28'
labels:
  - install
  - hardening
dependencies: []
priority: medium
type: enhancement
ordinal: 415204
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
FOUND 2026-10-13 on the Uganda box. Every SSH login from a Mac prints: -bash: warning: setlocale: LC_ALL: cannot change locale (no_NO.UTF-8): No such file or directory. Ubuntu sshd accepts LC_* forwarded by the client and the box does not have that locale, so the warning is a client and server mismatch, not a broken box. The owner already works around it with an alias on the server and suggested the hardening could do it for the operator. The cost is permanent noise that makes every installer transcript look broken.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 After hardening, a login from a client that forwards LC_ALL naming a locale the server lacks produces no setlocale warning. Checked by a login transcript recorded in the ticket.
- [ ] #2 The remedy is documented in the hardening documentation and does not silently override a locale the operator set deliberately.
- [ ] #3 If the chosen answer is to document the alias rather than automate it, that decision and the exact alias text are recorded here instead.
<!-- AC:END -->
