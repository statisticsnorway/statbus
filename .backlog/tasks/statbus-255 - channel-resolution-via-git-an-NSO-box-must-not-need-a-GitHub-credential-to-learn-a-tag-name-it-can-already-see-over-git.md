---
id: STATBUS-255
title: >-
  channel-resolution-via-git: an NSO box must not need a GitHub credential to
  learn a tag name it can already see over git
status: To Do
assignee: []
created_date: '2026-08-19 11:42'
updated_date: '2026-08-19 11:46'
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
<!-- COMMENTS:END -->
