---
id: STATBUS-341
title: >-
  github-auth-optional: token support for our boxes and willing NSOs — with
  anonymous sentinels kept by design
status: To Do
assignee: []
created_date: '2026-09-02 12:21'
updated_date: '2026-09-03 13:15'
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

## Comments

<!-- COMMENTS:BEGIN -->
author: foreman
created: 2026-09-03 13:15
---
KING'S RULING (2026-09-03), design amended and APPROVED for this build wave — supersedes the description's proposed split:

1. ONE NAME: GITHUB_TOKEN everywhere — the product already reads it for REST (github.go:144), workflows already export it. The .env.config entry uses the same name (entry-way documented, never auto-propagated); env wins over file. The release gate's anonymous deployability probes KEEP ignoring it by design (check.go:302 — the principled carve-out).
2. PURE ACCELERANT PRINCIPLE: token present → authenticated fetch+REST; absent → byte-identical to today. No forks, no migration, add/remove any time.
3. FLEET SPLIT (reverses the old proposal — sentinel = customer-fidelity ROLE, not the high-frequency boxes): dev TOKEN (5-min ticks, orchestrator-driven — this week's real victim), demo TOKEN (automated channel-follower), Norway ANONYMOUS SENTINEL (human canary lives the customer path; manual, 6h, low volume), country slots (et/jo/ma/ug) ANONYMOUS (King: low-frequency is fine anonymous).
4. HARNESS SPLIT: the two happy smokes STAY ANONYMOUS (they ARE the customer-experience test — sentinel duty); the wedge/recovery ARCS get the token (workflow GITHUB_TOKEN into the VM env) — they test recovery machinery, and anonymous 401 noise there is pure false-red (proven: 3 arc reds 2026-09-03 were storm-perturbed recovery-boot trajectories, zero arc defects).
5. Kept: read-only fine-grained repo-scoped token; 338 retry resilience remains primary defense; discovery/notify bounded-retry companion lands with this; sentinel list explicit + visible in cloud.sh status.

Context for urgency: 36h of GitHub 401-challenges on anonymous git-over-HTTPS from Hetzner IP space (authenticated paths: zero failures in the same windows) cost ~7 RC iterations and 3 arc false-reds. Queued alongside 344 for the post-promotion wave.
---
<!-- COMMENTS:END -->
