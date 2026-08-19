---
id: STATBUS-255
title: >-
  channel-resolution-via-git: an NSO box must not need a GitHub credential to
  learn a tag name it can already see over git
status: To Do
assignee: []
created_date: '2026-08-19 11:42'
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
