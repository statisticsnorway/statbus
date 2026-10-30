---
id: STATBUS-293
title: >-
  version-order-shas: CompareVersions silently falls back to lexical text
  against commit SHAs — a commit-installed box can be offered every release as
  an upgrade, including downgrades
status: Done
assignee:
  - '@engineer'
created_date: '2026-08-27 23:41'
updated_date: '2026-08-28 00:00'
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

author: engineer
created: 2026-08-27 23:56
---
**BUILT AND FROZEN — all four parts, 4/4 RED arms, full Go suite green uncached. Not committed. Two corrections to my own earlier claims below, both caught by verification, not review.**

## (1) The fix lives AT CompareVersions

`CompareVersions(a, b string) (ordering int, ordered bool)`. A new `calVerOrderableRegex` gates BOTH operands after the leading-`v` normalization; either side non-CalVer → `(0, false)`.

The gate sits **before the `a == b` fast path** deliberately: two identical commit SHAs are the same commit, but that is not a statement about release ordering, and the fast path would smuggle them through as "equal versions".

**The signature change IS the enforcement** — all 8 call sites had to be revisited, and the compiler produced that enumeration, not a human.

**Deliberately preserved:** double-`v` tolerance (`vv2026...`) still orders as before — a normalization-aware regex rather than `ValidateVersion`, so this fixes one behaviour without quietly changing a second.

## (2) Register nothing, loudly — both paths

`discover()` and `RunCheck` probe orderability by self-comparison (`CompareVersions(v, v)`) — cheapest probe that cannot drift from the gate — and refuse. RunCheck refuses **before** `runOneShot`: with nothing registrable, the poke would tell the service to prepare nothing. Both messages name **both ways forward**; verified `apply` is real (`cli/cmd/upgrade.go:99`) since AGENTS.md omits it.

`selectStaleBelowInstalled`: cannot compare ⇒ **retire nothing**.

**CORRECTION TO MY DIAGNOSIS.** I said `selectNewestDownloadCandidate` and `selectStaleBelowInstalled` "validate only the candidate, never `installed`". **Wrong** — both already guard it (4315, 4382). Only **two** of eight sites were ever unguarded: `discover()` and `RunCheck`, the two consuming `d.version` directly. The narrower story is truer: the pure helpers were right; the two paths a live box reaches were not.

**Explicit-target paths UNAFFECTED** — `registerStep`, `upsertCandidate`, `resolveUpgradeTarget`, `scheduleStep` call it nowhere. `register/apply <commit>` still works — what the arcs use, what 258 requires.

## (3) The derived pin, and an over-claim it refuted

`compare_versions_guard_test.go` uses 291's `functionsCalling` over both files, zero-scope guarded (≥7 consumers or the scan is declared broken).

**I first pinned only `ord, _ := ...`, arguing completeness because Go rejects unused variables so binding is self-enforcing. RED REFUTED IT:** `ord, ordered := ...` then `_ = ordered` compiled and sailed past. "Must be used" is not "must be consulted". Both spellings now caught; the corrected reasoning is left visible — the original sounded rigorous, was wrong, and only running the mutation caught it.

A second behavioural pin requires both paths to keep consulting the flag AND keep naming the escape route.

## (4) Harness — 11 arcs plus a 12th the scope didn't count

All 11 read `WHERE commit_sha = '$B_FULL'`, copying the form already correct in `claim-without-notify-arc.sh:88` (which passed in the failing run). Verified each references **only** `B_FULL`, no `C_FULL` — no blind substitution.

**12th site fixed:** `lib/assertions.sh:assert_upgrade_row_state` carried the same unfiltered query; shared, so it took an optional commit arg and all three callers pass `$B_FULL`.

## Verification

- **RED 4/4**: gate removed → red; gate always-true → red; `discover()` ignoring the flag → red; escape route removed → red. Restored byte-identical.
- Harness: Python, `-count=1`, **compiles each mutation before believing a red**, exclusive flock. Two harness bugs surfaced first (doubled `cli/` path; non-unique anchor), both caught by arms reporting "failed, but the expected test was not what caught it".
- `go build` + `go vet` clean; **full `go test ./... -count=1` GREEN**.
- `bash -n` clean across 38 files; **shellcheck delta ZERO** vs committed baseline via `git show`.

## Behaviour change reviewers should see

Two existing `TestCompareVersions` cases asserted an ordering for git-describe strings; they encoded the answers-anyway behaviour and now assert unorderable. No live path depended on them — `executeUpgrade`'s downgrade guard already required `ValidateVersion` on both sides, which a describe string fails. The table now carries the real SHAs (`063d860a` vs `5399acd8`) plus a symmetry test, so a future fix cannot gate only one operand.

**Either half independently fixes the six reds** — deliberate; they protect different failures.

NOT verified by me: that the arc fleet goes green. That needs the run.
---

author: foreman
created: 2026-08-28 00:00
---
LANDED at df9f0854e (18 files, +558/−70) after the architect's LAND — verified in the bytes: all call sites fail-closed in their correct directions ('!ordered ||' where the check must skip, 'ordered &&' where it must permit); both refusals verbatim to the ruling with the loop closed ('once the box is ON a tag, discovery resumes by itself'); the gate-before-a==b ruled LOAD-BEARING, not philosophical — self-comparison is the orderability probe three guards interrogate, recorded so no one 'optimises' the fast path forward and silently disables them; selectLatestTagFromNames' refuse-the-set-before-sorting called a genuinely good catch (an unorderable element in a sort comparator reports nothing). The pin's 'must be used is not must be consulted' correction accepted as a keeper, with the honest boundary noted at the line: the COMPILER is the primary enforcement and cannot be spelled past; the textual pin is second-line defence against laundering. THE PRE-CUT CONFIRMATION discharged by the foreman in the bytes: the 12th probe site (lib/assertions.sh:71-81) carries the optional commit argument with the WHERE commit_sha branch and all in-tree callers pass $B_FULL. Both self-corrections on the record (damage narrowed to the two d.version consumers; the pin refuted by its own mutation). rc.12 cuts on CI green at this tip; the fleet's verdict — the only oracle — arrives with its chain.
---
<!-- COMMENTS:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
A version comparator that returned a confident answer for input its own contract declared undefined is now structurally incapable of it: CompareVersions returns (ordering, ordered), the signature change forcing every caller through the compiler's enumeration, each fail-closed in its correct direction. A box installed at a bare commit — whose SHA's first hex digit previously decided whether it was offered every release in its channel as an 'upgrade', downgrades included — now registers nothing and says so loudly with both ways forward named; superseding skips what it cannot order; the deliberate register/apply path is untouched. The self-comparison orderability probe makes the unordered gate load-bearing ahead of the a==b fast path. The caller-guard pin is derived from source and survived refutation by its own mutation ('must be used is not must be consulted'), with the compiler as the floor and the pin as laundering defence. The harness's twelve probe sites read the row their diagnostics read. Found because rc.11's arc fleet became a lottery on random fixture SHAs; the fix makes fleet verdicts deterministic and removes a live downgrade-offer hazard from commit-installed production boxes. Landed at df9f0854e; rides rc.12.
<!-- SECTION:FINAL_SUMMARY:END -->
