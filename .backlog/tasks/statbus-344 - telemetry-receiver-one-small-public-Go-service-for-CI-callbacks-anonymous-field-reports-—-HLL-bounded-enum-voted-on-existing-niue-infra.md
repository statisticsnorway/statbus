---
id: STATBUS-344
title: >-
  telemetry-receiver: one small public Go service for CI callbacks + anonymous
  field reports — HLL-bounded, enum-voted, on existing niue infra
status: To Do
assignee: []
created_date: '2026-09-02 13:14'
labels: []
dependencies: []
priority: medium
type: feature
ordinal: 337000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
KING'S DIRECTION 2026-09-02 (supersedes and absorbs STATBUS-340 phone-home and STATBUS-343 ci-verdict-ledger — the 'underreach': one small specialized mechanism covering BOTH uses instead of contorting git refs, which structurally cannot take anonymous writes).

THE THING: a minimal Go web receiver (stdlib HTTP), publicly served via the EXISTING niue host Caddy (statbus_web already serves www.statbus.org there — one more SNI hostname/path + a systemd user unit in the established slot pattern; zero new infrastructure).

Faces:
- POST /ci — GitHub workflow_run webhook, HMAC-verified. Records {sha, workflow, conclusion, run_id, finished_at}.
- POST /report — ANONYMOUS box telemetry, no pre-registration: {version, channel, mode} + feature-usage votes from a FIXED ENUM baked into the binary (vote only for known things; unknown keys dropped at the door).
- GET — memory-speed queries: current verdict per sha+workflow; version/channel histogram (the 340 field directory, feeding the 339 fan); feature-usage estimates (what is used, what never).

GUARDRAILS (the design center): HLL for distinct-voter counts — ~KBs per counter at any scale, abuse-bounded (one IP moves an estimate once; botnets inflate linearly in distinct IPs only) and one-way (no IP is ever recoverable — the sovereignty/privacy answer: we structurally cannot know WHO, only HOW MANY). Finite votes per IP per window (LRU of (ip-hash,key)); per-IP token bucket; ~1KB payload cap; write-only-on-change; nothing received is ever reflected/served back verbatim; hourly state snapshot to one file, restart-cheap.

BOUNDARY: the release preflight's AUTHORITY stays GitHub — the receiver is a cache/telemetry plane; a lagging or compromised receiver must never green-light a cut. Boxes' opt-in stays a visible .env.config line (entry-way discipline); flag off = today's behavior exactly.

Deliverable this ticket: architect's full design (endpoint contract, state layout, HLL parameters, Caddy/unit wiring on niue, failure modes, what the preflight/watchers read and when they fall back to REST) for the King's ruling; build after the current release settles.
<!-- SECTION:DESCRIPTION:END -->
