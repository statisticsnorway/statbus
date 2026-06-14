---
id: STATBUS-050
title: >-
  supersede-stale-available: retire ledger rows older than installed
  (tier-independent) + reconcile prerelease labeling
status: To Do
assignee:
  - architect
created_date: '2026-06-14 07:19'
labels:
  - upgrade
  - ledger
  - bug
dependencies: []
references:
  - tmp/architect-047B2-upgrade-offered.md
priority: medium
ordinal: 50000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
DECISION (King, 2026-06-14): FIX NOW. From STATBUS-047 item B2. The SYMPTOM (UI offering an upgrade though at-latest) is a B1 leftover already handled by item A's decouple; THIS task is the latent data bug behind it.

## Root cause (verified live + in code, 2026-06-14 — foreman re-verified)
The ledger keeps phantom `available` rows older than the installed version. On rune (read-only): rows 133 (v2026.05.3-rc.01), 79 (v2026.05.2-rc.06), 74 (v2026.05.1-rc.01) are all `state='available'`, all `release_status='release'`, all OLDER than installed rc.02 (#196, 2026-06-12). They should be `superseded` and aren't. Two compounding causes:

1. SUPERSEDE HIERARCHY GUARD. `public.upgrade_supersede_older` (live source confirmed) retires older rows with `WHERE state IN ('available','scheduled','failed','rolled_back') AND commit_sha != p_commit_sha AND release_status <= _status AND committed_at < _committed`. Installing rc.02 (a prerelease) gives `_status=prerelease`, so `release_status <= prerelease` EXCLUDES `release`-tier rows → the 3 stale rows (labeled release) are never retired. The guard is correct for PEER supersede (a commit must not hide a tagged release) but wrong vs the INSTALLED version (anything older than what you run isn't an upgrade, regardless of tier).

2. PRERELEASE MISLABELING. The 3 rows are `-rc` tags but labeled `release`. Discovery (`service.go:2838`, `if !t.Prerelease`) trusts GitHub's release.Prerelease flag (false for these tags); the install path (`classifyReleaseStatus`, `cli/cmd/install.go:1813`) correctly parses `-rc.`→prerelease. The two paths DISAGREE. (NB the install path DOES call supersede — runInstallSupersede — so it's the guard blocking, not a missing call.)

Hidden on the UI only by coincidence (older version ⇒ older committed_at; page.tsx:559/567 drops available rows with committed_at ≤ newest-completed). A `/rest` consumer reading `state='available'` sees the phantom older versions. Truthfulness issue, not user-facing or recovery.

## Fix (architect's proposal, King-approved)
PRIMARY (durable, self-healing): on every discover() check, supersede any `available`/`scheduled` row NOT newer than the installed version (`d.version`), TIER-INDEPENDENT — same `CompareVersions` "newer than installed" rule discover() already uses to skip old tags (service.go:2827) and item A's pre-download selector uses. Self-heals regardless of install path or label.
SECONDARY (prevent recurrence): reconcile discovery's prerelease detection (service.go:2838 t.Prerelease) with classifyReleaseStatus so `-rc` tags are labeled `prerelease` in discovery too. NB OVERLAPS STATBUS-033 (prerelease-channel tag classification) — check whether to do together.
OPTIONAL: align the UI filter (page.tsx) to version-compare instead of committed_at, so it is robust without the date coincidence.

## Open question for execution (King cares — same lens as item A)
Does the PRIMARY fix touch the stored procedure (a MIGRATION — a new "supersede vs installed version" proc/mode) or stay in discover() Go logic (NO migration)? Decide + state explicitly.

## Verify
- Unit-test the version-compare retire decision (mirror item A's selectNewestDownloadCandidate test: newer/older/equal/non-CalVer/tier-independent).
- Confirm the 3 stale rune rows WOULD be retired by the new rule (read-only check vs rune data, or a fixture).
- go -C cli vet/build/test green (the per-change go-test gate runs on push).
- Report to foreman with the diff + the test for review + commit (do-not-self-commit).
<!-- SECTION:DESCRIPTION:END -->
