---
id: STATBUS-033
title: >-
  channel-filter-exclusivity: prerelease channel accepts ALL hyphenated tags —
  make channel→tag-shape filtering exclusive
status: In Progress
assignee:
  - engineer
created_date: '2026-06-12 05:44'
updated_date: '2026-06-14 20:48'
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

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
DISPATCH 2026-06-14 (foreman → engineer; King PULLED FORWARD right after STATBUS-050 — 'every time we defer it bites us'). Surfaced + verified while reviewing STATBUS-050. Verified file:line map (foreman, 2026-06-14):

- versionRegex (cli/internal/upgrade/github.go:62) = `^v\d{4}\.\d{2}\.\d+(-[\w.]+)?$` — the optional `(-[\w.]+)?` accepts ANY hyphenated suffix (-rc.N, -beta.1, -foo, a typo). This is why arbitrary hyphenated CalVer tags pass validation and enter discovery.
- FilterTagsByChannel (cli/internal/upgrade/github.go:455-467) — stable branch filters to no-hyphen (!t.Prerelease); PRERELEASE branch is `return tags // prerelease: all tags` (passes EVERYTHING). THE over-permissive site. So a stray -beta/experiment/typo tag shows on every prerelease box (dev included), one click from install.
- TWO divergent classifiers that disagree on NON-rc hyphenated shapes (AC#3 — unify into ONE shared shape-based classifier; no site may assume hyphen=prerelease):
  - discovery: service.go:2838 `if !t.Prerelease`, where t.Prerelease = github.go:443 `strings.Contains(tagName,"-")` = ANY dash → prerelease. (also service.go:2886 same pattern.)
  - installer: classifyReleaseStatus (cli/cmd/install.go:1813) — only `-rc.` → prerelease; a non-rc hyphenated CalVer like 2026.05.1-beta.1 falls through to SplitN(3) → 'release'. DISAGREES with discovery.

FIX (no migration — all Go):
1. FilterTagsByChannel → EXCLUSIVE allowlist: stable = no-hyphen CalVer only; prerelease = `-rc.` only; unknown / non-rc-hyphenated shapes match NO channel.
2. ONE shared shape→status/channel classifier, called by BOTH discovery and the installer; preserve the CORRECT -rc. behavior (both already agree there — don't regress it).
3. Unit test BOTH directions per channel (accept-list + reject-list), incl. an arbitrary non-rc hyphenated tag (e.g. v2026.05.1-beta.1) REJECTED by stable AND prerelease (AC#2).
4. go -C cli vet/build/test green.

NOT a bug for tags we mint today (only -rc. exists) — it's the latent footgun the moment any non-rc hyphenated tag appears; that's why it's pulled forward, not deferred.

FILE OWNERSHIP (this task, engineer only): cli/internal/upgrade/github.go, cli/internal/upgrade/service.go (discovery-classification region ~2825-2890), cli/cmd/install.go (classifyReleaseStatus). No other agent edits these meanwhile. do-not-self-commit — report to foreman with diff + test for review + commit.
<!-- SECTION:PLAN:END -->
