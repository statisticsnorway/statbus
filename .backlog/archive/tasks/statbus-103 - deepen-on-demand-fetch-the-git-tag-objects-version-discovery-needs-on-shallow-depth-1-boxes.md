---
id: STATBUS-103
title: >-
  deepen-on-demand: fetch the git tag/objects version-discovery needs on shallow
  (--depth 1) boxes
status: Done
assignee: []
created_date: '2026-06-20 10:35'
updated_date: '2026-06-20 10:52'
labels:
  - upgrade
  - git
  - version-discovery
dependencies: []
priority: low
ordinal: 103000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
▶ DRIVE DECISION + STATUS (King, 2026-06-20): TRACK + DRIVE TO DONE — do NOT park. RESOLVED 2026-06-20: INVESTIGATED → NO REAL GAP. Version discovery is robust on shallow (--depth 1) boxes; no deepen-on-demand fix needed. STATUS: Done.

WHY NO GAP (mechanic grounding + foreman verification):
- The RUNNING version is ldflag-injected (cli/Makefile:6 `-X cmd.version=$(VERSION)`; baked from a build-time `git describe` on the FULL clone in CI), NOT computed from git on the deployed box. So the discovery guard's d.version is correct on a shallow box without any tag lookup.
- All version-DISPLAY sites use `git describe --tags --always` → degrade gracefully to the bare SHA on a shallow box (cosmetic, non-fatal): config.go:490, service.go:3224/3616/3974.
- Candidate DISCOVERY (DiscoverTagsViaGit, github.go:484; sb upgrade check, upgrade.go:203) does `git fetch --tags` FIRST, which works on a shallow clone, then `git tag -l` (tag refs only). Online box → tags populate; offline → returns empty → no upgrade (safe).
- The ONE genuinely-shallow-broken op — MigrationInReleasedTag's `git rev-parse <tag>:<path>` (needs tree objects absent on shallow) — is BYPASSED for channelRelease (migrate.go:1380-1388, the STATBUS-102 #2b fix) and only otherwise reached on the localDev branch, which a deployed release box does not take.

CONCLUSION: no correctness gap on shallow boxes; the only degradation is a cosmetic version-display string. Closing as investigated/no-gap. Reopen if a real shallow-box version-discovery failure is observed.

----

(original) King-flagged 2026-06-20 (#3 of the channel-bless morning findings); decoupled from blessing (STATBUS-102 removed the bless's tag dependence). Investigated AC#1 → no real gap (above).
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Grounded: the exact version-discovery/describe call sites + git operations that depend on tags being present, and what each needs on a shallow clone
- [ ] #2 A targeted deepen-on-demand fetch (e.g. fetch the specific needed tag at depth) added at those points — not an --unshallow of the whole repo
- [ ] #3 Verified on a shallow (--depth 1) box that version discovery/describe returns correct info
<!-- AC:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
INVESTIGATED → NO REAL GAP. Version discovery is robust on shallow (--depth 1) boxes: the running version is ldflag-injected (build-time describe on the full clone), display sites degrade gracefully to SHA, candidate discovery fetches tags first (works on shallow), and the one tree-probe op (MigrationInReleasedTag) is bypassed for the release path. No deepen-on-demand fix needed. Closed as investigated/no-gap; reopen if a real shallow-box discovery failure is ever observed.
<!-- SECTION:FINAL_SUMMARY:END -->
