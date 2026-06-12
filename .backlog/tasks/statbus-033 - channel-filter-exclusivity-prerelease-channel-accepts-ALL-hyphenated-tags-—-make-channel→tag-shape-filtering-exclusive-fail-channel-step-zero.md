---
id: STATBUS-033
title: >-
  channel-filter-exclusivity: prerelease channel accepts ALL hyphenated tags —
  make channel→tag-shape filtering exclusive (fail-channel step zero)
status: To Do
assignee: []
created_date: '2026-06-12 05:44'
labels:
  - upgrade
  - channels
  - product
  - blocker-fail-channel
dependencies: []
references:
  - cli/internal/upgrade/github.go
  - cli/internal/upgrade/service.go
  - .backlog/docs/doc-010
priority: medium
ordinal: 33000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
VERIFIED LATENT FOOTGUN (architect, 2026-06-12, surfaced by the King's fail-channel design — doc-010). FilterTagsByChannel (cli/internal/upgrade/github.go:456-467) implements the prerelease channel as `return tags // prerelease: all tags`, and discover classifies ANY hyphenated tag as a prerelease (service.go:2790-2795). Consequence today: any future non-rc hyphenated tag shape (e.g. a `-fail.1` test fixture, or any experimental tag anyone pushes) is discovered and listed as an available upgrade on every prerelease-channel box — dev included — one UI click from installing it. Independent of the fail-channel feature, this is wrong-by-construction: a channel must be an exclusive allowlist of tag shapes, not "everything".

THE FIX: make channel→shape filtering exclusive — stable = CalVer no-hyphen only; prerelease = `-rc.` only; (future test channel = its own families only, added when the fail-channel feature lands). Unit test pins exclusivity in BOTH directions (each channel's accept-list and reject-list, including unknown shapes → rejected everywhere). Check the same shape-assumption at the other classification sites: discover's release_status derivation (service.go:2790-2795 "tags with - are prereleases") and any UI-facing status mapping.

SEQUENCING: lands with the gate-maker batch (small, standalone, no dependency on the fail-channel feature) — it must be on every box BEFORE the first `-fail.` tag ever exists (doc-010 §pre-requisite).
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 FilterTagsByChannel is an exclusive allowlist per channel: stable = no-hyphen CalVer only, prerelease = -rc. only; unknown/hyphenated-non-rc shapes match NO channel
- [ ] #2 Unit test pins both accept and reject lists per channel, including a -fail.N-shaped tag rejected by stable AND prerelease
- [ ] #3 discover's release_status classification (service.go:2790-2795) reviewed against the same exclusivity; no site still assumes hyphen=prerelease
- [ ] #4 Landed before any test/fixture tag is pushed to the repo
<!-- AC:END -->
