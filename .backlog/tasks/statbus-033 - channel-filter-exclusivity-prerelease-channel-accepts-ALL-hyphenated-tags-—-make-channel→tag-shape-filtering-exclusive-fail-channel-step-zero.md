---
id: STATBUS-033
title: >-
  channel-filter-exclusivity: prerelease channel accepts ALL hyphenated tags —
  make channel→tag-shape filtering exclusive
status: To Do
assignee: []
created_date: '2026-06-12 05:44'
updated_date: '2026-06-12 05:56'
labels:
  - upgrade
  - channels
  - product
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
VERIFIED LATENT FOOTGUN (architect, 2026-06-12; surfaced while reviewing the King's fail-channel design, but INDEPENDENT of it — the fail channel is branch-based per doc-010 and mints no tags). FilterTagsByChannel (cli/internal/upgrade/github.go:456-467) implements the prerelease channel as `return tags // prerelease: all tags`, and discover classifies ANY hyphenated tag as a prerelease (service.go:2790-2795). Consequence today: any hyphenated tag anyone ever pushes — an experiment, a typo, a future tag class — is discovered and listed as an available upgrade on every prerelease-channel box (dev included), one UI click from installing. A channel must be an exclusive allowlist of tag shapes, not "everything".

THE FIX: exclusive per-channel filtering — stable = CalVer no-hyphen only; prerelease = `-rc.` only; unknown shapes match NO channel. Unit test pins BOTH directions per channel (accept-list and reject-list, including an arbitrary hyphenated non-rc shape rejected everywhere). Review the sibling shape-assumption sites: discover's release_status derivation (service.go:2790-2795 "tags with - are prereleases") and any UI-facing status mapping.

SEQUENCING: small, standalone, no feature dependency — rides the gate-maker batch. The same exclusivity PRINCIPLE later extends to channel→branch mapping when the fail channel (STATBUS-034) lands, but nothing here waits for that.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 FilterTagsByChannel is an exclusive allowlist per channel: stable = no-hyphen CalVer only, prerelease = -rc. only; unknown/hyphenated-non-rc shapes match NO channel
- [ ] #2 Unit test pins both accept and reject lists per channel, including an arbitrary hyphenated non-rc tag rejected by stable AND prerelease
- [ ] #3 discover's release_status classification (service.go:2790-2795) reviewed against the same exclusivity; no site still assumes hyphen=prerelease
- [ ] #4 Ships in the gate-maker batch (deployed before any future non-rc hyphenated tag shape can exist in the repo)
<!-- AC:END -->
