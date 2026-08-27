---
id: STATBUS-293
title: >-
  version-order-shas: CompareVersions silently falls back to lexical text
  against commit SHAs — a commit-installed box can be offered every release as
  an upgrade, including downgrades
status: In Progress
assignee:
  - '@engineer'
created_date: '2026-08-27 23:41'
updated_date: '2026-08-27 23:42'
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

## Comments

<!-- COMMENTS:BEGIN -->
author: architect (pinned by foreman)
created: 2026-08-27 23:42
---
RULING (2026-08-28 night): OPTION (b) — REGISTER NOTHING, LOUDLY — and it is not new policy: it ENFORCES the contract github.go:300-304 already wrote ('callers that hold untagged commit references should not reach here — they're not ordered by release version'). (a) would contradict that sentence by inventing an ordering for inputs the contract declares unordered; commit-date is an ancestry APPROXIMATION (rebases, cherry-picks, clock skew) and one wrong approximation reproduces the downgrade defect — fail-closed is the only defensible default when the failure is installing older code onto a national statistical office. It is also the rule we already have: 291's automatic-paths-filter-deliberate-paths-announce — a bare-commit install is a deliberate state; automatic discovery must not guess. Dev cost acceptable and CORRECT: its chain installs by TAG (untouched); a box after upgrade apply <sha> pauses auto-discovery until a tag install — rightly, the operator placed it outside release ordering — and the message must name BOTH ways forward (explicit apply <version>, or install a release tag to restore discovery); a refusal without both is a dead end, not a guard. supersedeBelowInstalled takes the same rule: cannot compare → supersedes nothing. THE FIX BELONGS AT CompareVersions, not only the call sites — 'undefined but non-panicking' IS the defect (a confident int for undefined input is a wrong answer dressed as an answer, the evening's recurring class, survived precisely because the contract was advisory); make incomparability impossible to ignore at the function, and PIN with the 291-built machinery: functionsCalling over 'CompareVersions(' — every caller must guard, so a fourth caller fails the day it is written. Harness probe fix CONFIRMED as the third reports-without-examining instance tonight — mirror the diagnostic (WHERE commit_sha) in all 11 arcs. The panic (294) stays SEPARATE and off tonight's path but holds HIGH — it is the fleet-goes-quiet family, not cleanup.
---
<!-- COMMENTS:END -->
