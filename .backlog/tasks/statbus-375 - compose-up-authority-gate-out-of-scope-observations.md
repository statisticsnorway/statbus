---
id: STATBUS-375
title: >-
  compose-up authority gate: out-of-scope observations
status: To Do
assignee: []
created_date: '2026-09-18 13:16'
updated_date: '2026-09-23 15:10'
labels:
  - upgrade
  - recovery
  - security
dependencies: []
references:
  - STATBUS-369
priority: low
type: task
ordinal: 1
---

## Scope

The Compose-up authority gate in `doc/upgrade-recovery-model.md` proves absence
of **accidental reintroduction** of Compose-up authority in recovery code. The
owner closed that guard design at review round 10. This ticket records reviewer
observations outside the written threat model for completeness; they are not
release blockers and no action is planned.

## Out-of-scope observations from rounds 9-10

### Go plugin loading

Round-9 Luna tested `plugin.Open("evil.so")`. The type-resolved direct-launcher
gate did not catch it. `plugin.Open` is an indirect code-loading mechanism, not
one of the launcher APIs covered by the written model, so the reviewer
correctly recorded it as out of scope rather than as a bypass of the stated
proof.

### cgo source

Round-9 Luna also tested cgo source containing C-level
`system("docker compose up")`. This was not an uncovered bypass: the gate's
deliberate `CGO_ENABLED=0` package loads exclude such files, and its production
file coverage check reports a cgo file hidden from all typed loads. It is
recorded here because it was part of the explicit out-of-scope examination,
not because it leaves an open defect.

Round-10 Luna found no new out-of-scope bypass form. Round-10 Terra recorded no
additional out-of-scope observation. The in-scope round-9 findings about
mediator launchers and function-scoped dynamic `syscall.Exec` exceptions were
closed in round 10 and are not work for this ticket.

## Disposition

Open for traceability only. Revisit only if the threat model is deliberately
expanded from accidental process-launch reintroduction to arbitrary in-process
or foreign-code execution. No action is planned under the current model.

## Reconciliation 2026-09-23

Classification: PARTIAL. Evidence: compose-up authority fixes shipped, but the item is an observation ledger with remaining named follow-ups.

Remaining: Resolve the remaining explicitly listed compose-up authority observations or route each to its owning item.
