---
id: STATBUS-265
title: >-
  window-exempt-worker-recovery: exempt the worker's startup crash recovery from
  the upgrade's read-only window — it is system maintenance, not user work
status: To Do
assignee: []
created_date: '2026-08-27 12:48'
labels:
  - worker
  - upgrade
dependencies: []
priority: high
type: enhancement
ordinal: 258000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
From STATBUS-262: every upgrade starts the worker INSIDE the read-only accident-guard window by designed order (healthCheck at service.go:6931 precedes terminalExec(windowOffSQL) at :7039), so the worker's startup recovery can be refused in that gap.

Architect's ruling, upgraded from "defensible" to ratified-in-principle: exempt the worker's startup recovery the way the upgrade's own writers self-exempt (SET default_transaction_read_only = off on its session). The argument that settles it: a rollback restores the volume WHOLESALE, so the reset's rows revert regardless of whether it ran — the window's purpose is that a USER must not lose work they believed done, and the worker's crash recovery is not user work. The exemption cannot cost the rollback guarantee anything.

Constraint from the same ruling: an exemption on an accident-guard must be ARGUED AT THE LINE, never slipped in — the code comment carries this justification. Note: with this + STATBUS-264 landed, the upgrade's window/health-check ordering change is ranked unnecessary (deliberately not ticketed — see 262 final ruling).

WHAT IS ACHIEVED: the worker's crash recovery cannot be refused by the upgrade's own guard, removing the wedge cause rather than surviving it.
<!-- SECTION:DESCRIPTION:END -->
