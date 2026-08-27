---
id: STATBUS-293
title: >-
  version-order-shas: CompareVersions silently falls back to lexical text
  against commit SHAs — a commit-installed box can be offered every release as
  an upgrade, including downgrades
status: To Do
assignee: []
created_date: '2026-08-27 23:41'
labels:
  - upgrade
  - release
  - testing
dependencies: []
priority: high
type: bug
ordinal: 286000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Found by the rc.11 chain diagnosis (2026-08-28 night; empirically confirmed end-to-end on arc postswap-mid-tx-kill, run 33115731212): RunCheck gates candidate registration on CompareVersions(t.TagName, d.version) (service.go:4055-4057), where d.version on a commit-installed box is a bare commit SHA. CompareVersions (github.go:305) Atoi's segments and FALLS BACK TO LEXICAL STRING COMPARISON on failure — so it orders the literal text '2026' against the SHA: '2026' vs '5399acd8' skips correctly by luck ('2'<'5'), '2026' vs '063d860a' declares every CalVer release NEWER ('2'>'0') and registers the whole channel as available. github.go:300-304's own doc comment states the CalVer-only precondition and the undefined-ordering consequence; RunCheck violates it silently. supersedeBelowInstalled (service.go:4188) rests on the same comparison.

THE CLINCHER from the failing run: one job ran discovery twice — installed at 5399acd8: '8 match channel stable', zero Discovered lines; installed at 063d860a minutes later: same channel, same 8 tags, EIGHT Discovered lines. The only variable was the SHA's first hex digit.

PRODUCT EXPOSURE beyond the test harness: any box installed at a commit whose SHA begins 0 or 1 — install.sh --version <sha>, dev's upgrade-apply door, arc fixtures — is offered EVERY release in its channel as available, including releases months older than its code: a DOWNGRADE presented to an operator as an upgrade. Probability per random SHA: 2/16.

CONSEQUENCE OBSERVED: the upgrade arc fleet becomes a lottery (~1 in 8 per fixture commit) — six scenarios failed at rc.11 through phantom available rows (compounded by the harness probe bug fixed alongside: upgrade_state() read ORDER BY id DESC LIMIT 1, any newest row, while its own failure diagnostic read WHERE commit_sha — 11 arcs).

FIX SHAPE: architect ruling in flight — enforce the precondition rather than document it: a commit-installed box gets an explicit rule (commit-date ordering vs register-nothing-loudly), never a silent lexical coin-flip; the same rule covers supersedeBelowInstalled; the ShapeRelease/ShapePrerelease/ShapeCommit vocabulary already exists for detection.

WHAT IS ACHIEVED: no installation is ever offered software older than what it runs because of a string comparison, and the arc fleet's verdicts stop depending on random hex digits.
<!-- SECTION:DESCRIPTION:END -->
