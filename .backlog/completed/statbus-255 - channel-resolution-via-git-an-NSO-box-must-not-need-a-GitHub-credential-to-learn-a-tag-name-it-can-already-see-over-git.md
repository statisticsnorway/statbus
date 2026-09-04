---
id: STATBUS-255
title: >-
  channel-resolution-via-git: an NSO box must not need a GitHub credential to
  learn a tag name it can already see over git
status: Done
assignee: []
created_date: '2026-08-19 11:42'
updated_date: '2026-08-19 19:23'
labels:
  - upgrade
  - ops
  - bug
dependencies: []
priority: high
type: bug
ordinal: 248000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
All seven niue slots share one IP, and every `./sb upgrade check` resolves its channel through the GitHub RELEASES API unauthenticated — 60 requests/hour for the whole fleet. On 2026-08-19 the window exhausted and all seven notify jobs failed with 403 (run 32247740861); dev now polls every 5 minutes, so this recurs structurally, and any statistical office behind a shared IP inherits the same failure.

THE SILLY PART, verified at source: the service already HAS the unlimited path — DiscoverTagsViaGit (github.go:478) does `git fetch --tags`, no API, no credential, no limit. But ResolveChannelToLatestTag (github.go:315-329, the SOLE resolution site for install.sh, `./sb install`, and `./sb release check --channel`) calls FetchReleases (github.go:185) — the API — to read GitHub's prerelease FLAG. That flag is fully derivable from the tag name itself: `-rc.` means prerelease, the exact rule ops/create-new-statbus-installation.sh already applies via plain git. Authentication is only picked up if GITHUB_TOKEN happens to be in the env (github.go:158-160); the boxes rightly have none.

THE FIX (King ruled 2026-08-19: "make a ticket to fix that silly thing"): channel resolution derives from git tags — DiscoverTagsViaGit + tag-name classification — with no API call and no credential. The API remains only where genuinely needed (e.g. release-asset metadata at install time; note asset downloads via browser_download_url are not API-rate-limited). The customer frame decides the shape: an African NSO box must never need a GitHub token to follow a release channel.

WHAT IS ACHIEVED: fleet discovery stops sharing a 60/hour budget, the notify workflow stops failing on quota, and channel-following works identically for every external standalone customer regardless of their network.
<!-- SECTION:DESCRIPTION:END -->

## Comments

<!-- COMMENTS:BEGIN -->
author: engineer
created: 2026-08-19 11:46
---
**BUILT AND FROZEN — but read the finding first, because THE FIX AS SCOPED DOES NOT STOP THE 403s.** Files: `cli/internal/upgrade/github.go`, new `channel_resolution_git_test.go`. Chain green.

**THE FINDING, verified at source: `./sb upgrade check` — the command the ticket names as failing — does NOT go through `ResolveChannelToLatestTag`.** `RunCheck` (service.go:5047-5049) calls `FetchReleases()` **directly**, then registers every newer release as a candidate. So resolving the channel over git closes one API caller and leaves the one that actually 403'd the fleet untouched. The ticket's premise — that resolution is the path `./sb upgrade check` takes — does not hold; they are two separate API callers, and only one is in this unit's scope.

**WHAT `RunCheck` ACTUALLY NEEDS FROM THE API, enumerated as instructed** (service.go:5067-5085). Per release it consumes exactly four things:
- `r.TagName` — git has it.
- `r.TargetSHA` — git has it, **and RunCheck already falls back to `d.RevParse(tag)` when the payload omits it**.
- `r.Published` — `DiscoverTagsViaGit` already returns `PublishedAt`.
- the release status — **already derived by tag name**: `ClassifyReleaseShape(r.TagName).ReleaseStatus()`. It does not read GitHub's prerelease flag at all.

`GitTag` carries `TagName`, `CommitSHA`, `PublishedAt` — all four needs are covered. **Nothing in `RunCheck` requires release metadata beyond what git already provides**, which is the answer the ruling asked me to establish before deciding.

**SO WHY I DID NOT JUST CHANGE IT — there is one real semantic difference, and it is a King/architect call, not mine.** `FetchReleases` returns PUBLISHED RELEASES; git tags include EVERY tag, including one pushed without a GitHub release. Moving `RunCheck` to git would let such a tag become a candidate — a version with no assets to install. Mitigation already exists (discovery verifies the release via `FetchManifest` at service.go:4111 and marks `release_builds_status` failed when it is absent), so the failure would be loud rather than silent — but it IS a behaviour change to what counts as a candidate, and the instruction was to name it rather than fold it in silently.

**WHAT IS BUILT.** `ResolveChannelToLatestTag` now derives from `DiscoverTagsViaGit` + `ClassifyReleaseShape` — no API, no credential, unlimited. It stays the SOLE resolution site for install.sh, `./sb install`, and `./sb release check --channel`; a testable `…At(projDir, channel)` inner variant was added rather than a second resolver, because a second one would let those three disagree about what a channel points at.

**Classification REUSES `ClassifyReleaseShape`** — the same rule `ops/create-new-statbus-installation.sh` applies over plain git — rather than a second `strings.Contains(tag, "-rc.")`. A test fails if that literal ever appears in the selector: two copies of "what counts as a prerelease" drift, and this copy decides which version a box installs.

**EQUIVALENCE PROVEN, not assumed.** A test resolves the SAME tag set through the old API selector and the new git selector and requires identical answers on both channels — including a release-cutting day where a stable tag and a newer RC coexist. This had to be a rate-limit fix, not a behaviour change wearing one.

**Preserved deliberately:** the prerelease channel means LATEST RC, so a stable tag at HEAD must not win it (pinned — getting it wrong would silently move every prerelease box onto stable); `-beta.` and other non-rc suffixes match NO channel, exactly as before; edge still resolves to the empty tag; an unknown channel still ERRORS rather than returning an empty tag, which would read as “nothing to upgrade to” and freeze a box on a typo.

**One thing the API had that git cannot see, stated rather than discovered later:** GitHub's DRAFT flag. A draft publishes no git tag, so drafts are invisible here — the behaviour we want, now reached by construction instead of by a filter.

**Zero-API pinned structurally** on both resolution functions (no `FetchReleases`, no `apiBase`, no `http.NewRequest`), with the failure message carrying the 60/hour-shared-IP reason so the next person understands why the pin exists.
---

author: foreman
created: 2026-08-19 11:53
---
RESOLUTION HALF LANDED as 567487c47 (architect ruled 'land as-is'): ResolveChannelToLatestTag now derives from DiscoverTagsViaGit + ClassifyReleaseShape — no API, no credential, unlimited — with equivalence PROVEN old-vs-new on both channels including the stable+newer-RC coexistence day, one resolution site preserved via the ...At(projDir, channel) variant, and a pin against a second '-rc.' literal ever appearing. TICKET STAYS OPEN — the architect's ruling states it plainly: this landing does NOT fix the reported 403 symptom. RunCheck (service.go:5047-5049) calls FetchReleases DIRECTLY and is where the fleet's quota actually burns; its switch to git is the ticket's remaining body, ruled a SEPARATE unit (a semantic change must not ride an equivalence-proven refactor — the same ruling for the third time). Its first step is EVIDENCE, not reasoning: read the failure-marking guard to learn whether a git-derived candidate in the tag-pushed-but-release-unpublished window lands in 'building' (self-resolving, fine) or 'failed' (transient red on every box on every release — unacceptable, needs handling first); the imminent cut offers a free live observation of the real timing.
---

author: engineer
created: 2026-08-19 12:04
---
**Second half built and FROZEN — deliberately NOT landed** (post-cut unit; it rides the next candidate after the tag).

**The purpose:** the first half made channel RESOLUTION credential-free, but the fleet would still have 403'd, because the command that actually exhausted the quota never went through the resolver. This closes the real source, so that no automatic path a box takes to learn what versions exist reaches api.github.com at all.

**What was wrong.** `RunCheck` — `sb upgrade check`, the polling command — called `FetchReleases()` directly (service.go:5171). 60 requests/hour per IP; seven niue slots share one; dev polls every five minutes. Fixing only the resolver would have closed the wrong caller and left the fleet failing exactly as before.

**What it now does.** `RunCheck` discovers over `DiscoverTagsViaGit(d.projDir)`. Every field it needs was already in git, and one of them was never GitHub's to begin with:
- tag name — git;
- commit — git IS the authority, and the old path already fell back to `RevParse` when the API payload omitted it, so that fallback is kept unchanged;
- timestamp — git;
- release status — already derived from the TAG NAME via `ClassifyReleaseShape`, never from GitHub's prerelease flag. The API call was buying nothing here.

**The one real behavioural difference, verified rather than assumed** (this was the evidence step, done before writing the change). The API returned PUBLISHED RELEASES; git returns every tag, including one pushed before its release exists. Such a tag can now become a candidate — and it cannot be installed: `verifyArtifacts` marks `release_builds_status` when the manifest is absent (service.go:4111-4144), and the scheduled path then UNSCHEDULES it with "Release assets not ready for %s — unscheduled. Will be available when CI finishes." (service.go:5604-5634). The failure mode is a visible wait that self-corrects when CI lands, not a broken box. That guard is the premise this change rests on, so the test asserts it too: if it ever disappears, git-derived discovery becomes able to attempt an install against a tag with no binary, and the pin fails loudly rather than silently inheriting the risk.

**Test** — `TestDiscoveryMakesNoAPICall_STATBUS255` in `channel_resolution_git_test.go`, RED-verified by mutation both ways: adding a compiling `FetchReleases()` call back into `RunCheck` fails it; renaming the readiness message fails it.

One process note worth recording, because it nearly produced a fake green. My first RED attempt appeared to pass. The mutation had matched the FIRST occurrence of the target line in the file (:4029, a different function) rather than the one inside `RunCheck` (:5195) — so the mutation was real, compiled, and tested nothing. A RED that does not fire is not evidence the code is right; it is evidence the experiment missed. Re-run against the correct line, both mutations fail as intended.

Chain: build OK, `go test ./...` green, `golangci-lint run ./internal/upgrade/` 0 issues, `gofmt` clean on both touched files (the repo's pre-existing `gofmt -l` drift is in untouched files and was left alone).

**A fork is reported separately to the foreman rather than absorbed:** with this switch, `FetchReleases` has zero production callers, as does `selectLatestTag` (test-only now) and `FetchCommits` (already dead before this change). Deleting them is the clean-break instinct, but `selectLatestTag` is the ORACLE for the equivalence test that proves this entry did not change behaviour — so the deletion has a consequence worth a ruling, not a silent call.
---

author: engineer
created: 2026-08-19 12:05
---
**Correction/sharpening of #3 — the architect's binary question is answered decisively, and the answer is the GOOD branch.** Comment #2 asked whether a git-derived candidate in the tag-pushed-but-release-unpublished window lands in `building` (self-resolving, fine) or `failed` (transient red on every box on every release, unacceptable). I stated the mitigation in #3 but not which branch it takes. Reading the code rather than inferring it:

`release_builds_status` is `NOT NULL DEFAULT 'building'` (doc/db/table/public_upgrade.md:30), and discovery writes it in exactly two places (service.go:4110-4149):
- manifest fetch SUCCEEDS → `'ready'`;
- manifest fetch FAILS **and** the release workflow has a COMPLETED run whose conclusion is `failure` with no `success` → `'failed'`.

There is no third write. In the window the architect asked about — tag pushed, release not published yet, CI still running — the manifest is absent but there is no completed failing run, so **nothing is written and the row stays at its default `building`**. That is the self-resolving branch, and it flips to `ready` on the next discovery cycle once CI publishes. The unacceptable `failed` state is reserved for a genuinely failed release workflow, which is a true red worth showing.

The same holds on a box with no GitHub credential: the CI check shells out to `gh api` (:4119), so on an NSO box it simply errors, nothing is written, and the row again stays `building`. The credential-free frame is preserved on this path too — the absence of a token degrades to "keep waiting", never to a false red.

So the semantic change this unit introduces is bounded to: *a tag may appear as a candidate slightly earlier than before, in `building`, and resolve itself.* No box can install it (the scheduled path unschedules with the visible "Release assets not ready … Will be available when CI finishes" wait), and no box shows a false failure.
---

author: engineer
created: 2026-08-19 12:22
---
**DELETION DIFF BUILT AND FROZEN** — the third and last unit of this ticket, its own diff, executed in the ruled order. Chain: build OK, `go test ./...` green, `golangci-lint run ./...` 0 issues, gofmt clean. 123 lines out of `github.go`.

**The purpose:** remove the GitHub-API discovery path from the tree entirely, so that nobody can reach for it again and silently reintroduce the 403 this ticket exists to kill — without losing the proof that the git path answers identically.

## The order was the ruling, and here is what each step actually produced

**(1) The fixed oracle.** `apiRuleOracle` states the rule the API path applied, as intent rather than as a reference to an implementation: edge resolves to no tag; stable takes the highest-CalVer release GitHub did NOT flag prerelease; prerelease takes the highest-CalVer one it DID (deliberately not "all releases" — the operator-facing meaning is LATEST RC, so a stable tag at HEAD must not win it on a release-cutting day); drafts are never eligible; anything else errors rather than returning an empty tag, which would read as "nothing to upgrade to" and freeze a box on a typo.

**(2) Verified against the original, while both existed.** `TestFixedOracleTranscribesTheLiveRule` drove the oracle and the live `selectLatestTag` over the same inputs — six sets × five channels, 30 comparisons — covering the release-cutting day, drafts, a channel with nothing published, an empty set, edge, and an unknown channel. Identical on every one.

I also RED-verified the CHECK ITSELF before trusting it, asserting the mutation site per the rule from the last unit: breaking the oracle's draft exclusion fires it, and widening its prerelease filter to "all releases" fires it. A transcription check that cannot fail would have proven nothing, and it would have looked exactly like a passing one.

**(3) Only then, the deletion.** `FetchReleases`, `selectLatestTag`, `FetchCommits` — plus the `Commit`/`CommitDetail` types, which existed solely to carry `FetchCommits`' response, and an import left orphaned by the cut.

The equivalence proof now compares the git resolver against the fixed oracle instead of a function that no longer exists. The transcription check is gone with its subject, and a note stands in its place recording that it ran, what it covered, that it agreed, and why it can never be run again — so a later reader does not mistake its absence for an omission.

**Why the order is not a preference, stated at the line:** a fixed oracle carries exactly one risk — a wrong transcription — and that risk is checkable during exactly one instant, while the original is still in the tree. Verifying after the deletion is not slower; it is impossible.

## Coverage accounting for the test that died with its subject

`TestSelectLatestTag` tested the deleted implementation. Rather than delete it silently, its cases are accounted for in a note where it stood: "stable picks latest CalVer" and "prerelease picks latest RC" are covered against the LIVE resolver (including the coexistence day); "edge returns empty" and "unknown channel errors" likewise; and **"only-draft does not satisfy stable" is now true BY CONSTRUCTION rather than by a filter** — a GitHub draft publishes no git tag, and resolution reads git tags, so there is nothing left to filter and nothing left to test.

## ONE FURTHER FINDING, reported not absorbed — the dead island is bigger than three

With `FetchReleases` gone, **nothing in production can construct a `Release` any more.** `FetchReleases` was its only producer. That leaves `FilterByChannel` and `ReleaseSummary` with zero production callers (`ReleaseSummary` lost its last one when `RunCheck` switched to git), and the `Release` type itself reachable only from tests — a closed, provably unreachable island rather than merely two more orphans.

I did NOT delete them: the ruling named three functions and fixed the order for this diff, and a fourth deletion changes the diff under review. The evidence is unambiguous if it should follow. One design point belongs with that decision: `apiRuleOracle` currently takes `[]Release`, and if the type goes it should carry its own local shape — which is arguably better anyway, since a FIXED oracle should not depend on a production type that may drift.
---

author: foreman
created: 2026-08-19 19:17
---
LANDED, ticket complete. Three commits: 567487c47 (resolution via git, landed pre-freeze), f709d5eb6 (RunCheck discovers over git — the caller that actually 403'd the fleet), c4ba87464 (API path deleted: FetchReleases, selectLatestTag, FetchCommits, FilterByChannel, ReleaseSummary; equivalence preserved via the fixed apiRuleOracle verified 30-comparisons against the live original before deletion). One boundary correction during landing, architect-ruled: the Release/Commit/CommitDetail types stayed one commit longer — their last consumers were the edge machinery, and a type dies in the commit that removes its last user (1dff9c18f). Also folded during landing: the fmt+sort imports of channel_resolution_git_test.go belonged to the first commit (its code used them; caught by per-commit go vet in a throwaway worktree). Each intermediate commit build+vet verified independently. Dev incident of 2026-08-19 (separate thread) confirmed the motivating symptom live: dev's service discovering 186 prereleases via git every 5 minutes, zero API calls.
---

author: foreman
created: 2026-08-19 19:21
---
CORRECTION TO THE LANDED COMMIT MESSAGES, recorded here because the commits are pushed and immutable. c4ba87464's message says the Release type 'stays one more commit: the edge machinery holds its last uses', and 1dff9c18f's trailing paragraph repeats the attribution. Both are WRONG about the reason: the type's actual surviving consumers at the unit-3 boundary were FilterByChannel and ReleaseSummary — API-path functions the split's classifier had misfiled into the edge-retirement diff (pure-deletion hunks carry no added lines, so it filed them by enclosing region). The CODE at every commit is correct and was build+vet verified per commit in isolation; what is impure is that 1dff9c18f (edge retirement) also carries ~100 lines of API-path corpse deletion (FilterByChannel, ReleaseSummary, Release/Commit... wait — Commit/CommitDetail died in c4ba87464 with FetchCommits, correctly). The engineer's post-hoc analysis (their re-split, produced in parallel and not landed) confirms both boundaries compile; theirs was thematically cleaner (everything API-dead in unit 3). Landed history stands; this comment is the truth a future reader needs when the message and the diff disagree.
---

author: foreman
created: 2026-08-19 19:23
---
CORRECTION TO COMMENT #7, engineer-verified at source and foreman-re-verified by grep — this supersedes #7's mechanism story. At c4ba87464 (landed unit 3) FilterByChannel and ReleaseSummary are ALREADY DELETED — they died with the functions, in unit 3, correctly. The Release type therefore spent one commit as a FULLY ORPHANED declaration: nothing referenced it at c4ba87464, and 1dff9c18f removed exactly the declaration plus doc comment, zero consumers. So both landed commit messages are wrong the same way: they invoke the last-consumer rule while the landed boundary orphans the type for one commit — the honest sentence would have been 'the Release type is carried one more commit and removed alongside the edge retirement, keeping this commit a pure removal of the API functions'. The wording had been written for the OTHER boundary (consumers travelling with the type), where it was true; it inverted when applied to this one. Lesson, engineer's phrasing kept: A MESSAGE TRAVELS WITH A BOUNDARY — moving one without re-reading the other is how a commit documents a different change than it makes. Code verified correct at every commit by two independent methods (per-commit worktree build+vet at landing; engineer's pristine-archive build+vet of all five afterwards). Record closed.
---
<!-- COMMENTS:END -->
