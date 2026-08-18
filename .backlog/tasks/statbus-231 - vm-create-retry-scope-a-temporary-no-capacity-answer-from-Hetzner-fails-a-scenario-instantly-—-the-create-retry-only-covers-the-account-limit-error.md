---
id: STATBUS-231
title: >-
  vm-create-retry-scope: a temporary "no capacity" answer from Hetzner fails a
  scenario instantly — the create retry only covers the account-limit error
status: To Do
assignee: []
created_date: '2026-08-18 10:54'
labels:
  - install-recovery
  - ci
  - infra
dependencies: []
references:
  - test/install-recovery/lib/vm-bootstrap.sh
  - tmp/operator-ir-triage-2026-08-18.md
priority: low
type: enhancement
ordinal: 231000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Test scenarios rent a machine each; when the provider momentarily has none to give, the right response is to wait and ask again — the shortage clears in minutes. Today two scenarios failed instantly instead, costing their coverage for the whole run.

WHAT THE EVIDENCE SHOWS: at the rc.03 install-recovery run (32115159128), both 0-happy scenarios died 48 seconds in at `hcloud server create` with "error during placement (resource_unavailable)" — Hetzner had no capacity to place the VM at that moment, likely because the run's first provisioning wave asked for several at once. The failure was loud and honest (the message names the cause; not the 227 starvation class, not a cancellation). But the create retry added in the fleet hardening (5 attempts x 60s) triggers ONLY on the literal `resource_limit_exceeded` string — the account-quota error — so this different, equally-transient error skipped the retry entirely.

THE FIX: widen the retry trigger to also match placement `resource_unavailable` (and consider whether any other transient hcloud error classes belong; permanent errors like auth failures must still fail fast). Same bounded retry, no new machinery.

WHAT IS ACHIEVED: a minutes-long capacity blip at the provider costs a scenario a short wait instead of its whole verdict — fewer red runs that mean nothing about the product.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 The create retry fires on placement resource_unavailable as well as resource_limit_exceeded; permanent error classes still fail fast
- [ ] #2 A scenario surviving a transient placement shortage is observed (or the retry path is test-pinned if observation is impractical)
<!-- AC:END -->
