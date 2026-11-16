---
id: doc-011
title: 'SUPERSEDED — see ticket STATBUS-059 (design lives in tickets, not documents)'
type: specification
created_date: '2026-06-15 22:24'
updated_date: '2026-06-15 22:44'
tags:
  - upgrade
  - recovery
  - robustness
  - design
  - rc.03
---
# SUPERSEDED

Design lives in **tickets**, not documents (King convention). The upgrade crash-window robustness design of record is now **STATBUS-059** (`preswap-checkout-forward-fix`).

- STATBUS-058 — the config-drift bug + the shipped/in-progress daemon fix (F1 + the unconditional config-regen-before-EnsureDBUp).
- STATBUS-059 — the forward fix: image-extract sb procurement + defer-checkout, the King decisions (D1 ruled YES), and the legacy/install.sh analysis.
- STATBUS-026 — the harness fidelity variant (genuine pre-fix binary).

This document is intentionally emptied to avoid a second source of truth.
