---
id: STATBUS-489
title: Hardening should spare the operator a locale warning on every login
status: Done
assignee: []
created_date: '2026-10-13 12:28'
updated_date: '2026-10-13 14:12'
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
- [x] #1 After hardening, a login from a client that forwards LC_ALL naming a locale the server lacks produces no setlocale warning. Checked by a login transcript recorded in the ticket.
- [x] #2 The remedy is documented in the hardening documentation and does not silently override a locale the operator set deliberately.
- [ ] #3 If the chosen answer is to document the alias rather than automate it, that decision and the exact alias text are recorded here instead.
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Remedy (a), chosen deliberately: the box should actually carry the locale the operator declared, rather than paper over the warning with a per-user alias. Root cause on the Uganda box: macOS forwards LC_ALL=no_NO.UTF-8, and glibc ships no no_NO locale at all, so even a correctly generated nb_NO.UTF-8 did not help. The old loop also appended .UTF-8 to the operator's input, so typing nb_NO.UTF-8 searched for 'nb_NO.UTF-8.UTF-8 UTF-8' and printed 'not found' (the inconsistency in the log). Fix: enable_extra_locales() strips any suffix, enables <base>.UTF-8, and when nb_NO is declared appends 'no_NO.UTF-8 nb_NO.UTF-8' to /etc/locale.alias ONLY if no no_NO.UTF-8 alias exists, so an operator's own choice is never overridden. Commit 7e38edfc4.
RED (before helper existed): FAIL enable_extra_locales() not found in setup-ubuntu-lts.sh, exit=1.
GREEN test/install-recovery/tests/setup-extra-locales-test.sh: PASS suffix-typed nb_NO.UTF-8 enabled / sq_AL enabled / no spurious not-found warning / no_NO.UTF-8 aliased / rerun idempotent / operator's own no_NO alias untouched, exit=0.
Real Ubuntu 24.04 transcript (docker): before: 'LC_ALL=no_NO.UTF-8 bash -c date' -> 'bash: warning: setlocale: LC_ALL: cannot change locale (no_NO.UTF-8)'. After enable_extra_locales nb_NO.UTF-8 + locale-gen: 'nb_NO.UTF-8... done', locale -a lists nb_NO.utf8, same login command prints 'tirsdag' with no warning. Fallback alias for clients with other locales is no longer needed for Norwegian. Documented in doc/setup-ubuntu-lts.md (EXTRA_LOCALES row).

CI on 7e38edfc4: Harness Selftest run 38410765777 job harness-selftest success, STATBUS-489 step success (also 38410744181 success).
<!-- SECTION:NOTES:END -->
