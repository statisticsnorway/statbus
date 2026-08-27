---
id: STATBUS-291
title: >-
  check-channel-filter: the CLI upgrade check registers candidates without
  consulting the channel — a production box lists and can schedule an rc
status: To Do
assignee: []
created_date: '2026-08-27 20:08'
labels:
  - upgrade
  - release
  - cli
dependencies: []
priority: high
type: bug
ordinal: 284000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Found live on ua (2026-08-27, channel=stable via role=production): after the discovery fix, `./sb upgrade check` registered v2026.08.0-rc.11 and `upgrade list` shows it as `available` on a stable-channel box — the exact surface the release topology promises production boxes never see (the 254 class).

Engineer's code-read, verified both directions: the SERVICE's discovery path filters correctly — FilterTagsByChannel at service.go:4047 inside discover(); everything downstream iterates the filtered set. The CLI's RunCheck (service.go:5149) does NOT — it loops the RAW DiscoverTagsViaGit output with only a CompareVersions newer-than-installed guard (:5188); FilterTagsByChannel appears nowhere in the function. `available` in upgrade list is merely a registered row in public.upgrade (state sets :1620/:1709), not a filtered offer. AND scheduleStep (:5041) consults no channel either — its refusals are target-resolution/park/artifact gates — so a human who schedules the listed rc on a production box hits no channel refusal. Accountability checked, not assumed: the pre-255 implementation had the same absent filter (git show f709d5eb6^) — 255 ported it faithfully while widening the input (git discovery returns every tag, including unpublished ones), so the unfiltered list shows MORE now, though the gap is old.

DESIGN FORK for the architect, then one-line-plus-test build: (a) apply FilterTagsByChannel(tags, d.channel) in RunCheck immediately after DiscoverTagsViaGit, mirroring :4047, making the two discovery paths agree — plus a declarative test asserting BOTH paths filter so they cannot diverge again; or (b) keep registration wide and gate at the offer/list/schedule boundary — a bigger question about what a registered row MEANS. Note the filter must stay channel-aware, not rc-blocking: canary boxes (dev, Norway) legitimately see rcs.

Interim exposure assessment: requires a human running check+schedule on a production box — precisely what an operator following the canonical workflow does. The remaining protections are artifact/park gating, not channel policy.

WHAT IS ACHIEVED: a production box's operator can neither see nor schedule software the topology never offered it, and the two discovery paths can never silently disagree about the channel again.
<!-- SECTION:DESCRIPTION:END -->
