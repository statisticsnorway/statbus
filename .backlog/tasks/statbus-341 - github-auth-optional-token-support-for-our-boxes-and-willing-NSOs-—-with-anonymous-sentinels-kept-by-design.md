---
id: STATBUS-341
title: >-
  github-auth-optional: token support for our boxes and willing NSOs — with
  anonymous sentinels kept by design
status: To Do
assignee: []
created_date: '2026-09-02 12:21'
labels:
  - ops
  - upgrade
  - resilience
dependencies: []
priority: medium
type: enhancement
ordinal: 334000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
GitHub-transient incidents (rune rc.02 preswap fetch; dev notify git fetch --tags, same day, same signature: anonymous smart-HTTP answering an auth challenge) motivate OPTIONAL authenticated HTTPS — with a deliberate limit the King set: we must keep living the anonymous path our customers cannot escape.

Design for ruling before build:
1. HTTPS stays the transport (SSH needs a key; customers have none). Anonymous stays the product default and the tested norm.
2. Optional token support: a documented .env.config entry (entry-way file discipline — creation-header documentation, never auto-propagated) that, when present, authenticates git fetch + REST calls (5000/h vs 60/h; no anonymous auth-challenge). Usable by us or by any NSO with its own credential. Read-only fine-grained token, repo-scoped.
3. NO-MONOCULTURE REQUIREMENT (the King, 2026-09-02): some of our own boxes MUST stay anonymous by design so we know the tokenless path works — the sentinels. Proposed split: canaries (dev, rune) stay anonymous — their role is to hit what customers hit; stable production slots may take the token. The split is recorded per box and verifiable (cloud.sh status could show it).
4. Primary defense remains STATBUS-338's resilience (local-objects fast path, bounded retry) — the token is comfort, not correctness.
5. Small companion: give discovery/notify ticks the same bounded transient retry preswap got (today a Notify job reds on one blip; a retry makes it a non-event). May land independently of the token.

Acceptance (post-ruling): token entry documented at its point of entry; fetch/REST paths use it when present; at least dev + rune verified running anonymous (the sentinel list is explicit, not accidental); discovery/notify retry landed; a tokenless box behaves identically to today.
<!-- SECTION:DESCRIPTION:END -->
