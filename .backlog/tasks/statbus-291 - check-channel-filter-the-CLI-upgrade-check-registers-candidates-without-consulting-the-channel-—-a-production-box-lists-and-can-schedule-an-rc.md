---
id: STATBUS-291
title: >-
  check-channel-filter: the CLI upgrade check registers candidates without
  consulting the channel — a production box lists and can schedule an rc
status: In Progress
assignee:
  - '@engineer'
created_date: '2026-08-27 20:08'
updated_date: '2026-08-27 20:10'
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

## Comments

<!-- COMMENTS:BEGIN -->
author: architect (pinned by foreman)
created: 2026-08-27 20:10
---
RULING (2026-08-27): OPTION (a) — filter in RunCheck, mirroring :4047. Option (b) is not 'moving the gate': the meaning of a registered row ALREADY EXISTS and discover() set it (every service-written row is channel-appropriate because :4047 filters before the upsert loop) — RunCheck is the outlier, not the definition; (b) would leave rows meaning two different things depending on which path wrote them. AND THE LIST IS THE OFFER: a stable-channel operator who sees rc.11 as 'available' reasonably concludes it is installable; a schedule-time refusal arrives after intent has formed and reads as the tool contradicting itself — do not offer what you will not install; the harm is the offer, not only the install. PLACEMENT CONSTRAINT THAT DECIDES WHETHER 258 SURVIVES: the filter goes in RunCheck (:5149) after DiscoverTagsViaGit and must NOT go in the shared upsertCandidate (:3977) — registerStep (:4997) calls it and that is the King's candidate-addressed deliberate path; verified distinct (discovery vs explicit verb), so the verbs stay distinct under (a). THE SCHEDULE HALF gets the opposite treatment — the general rule, named for future sites: AUTOMATIC PATHS FILTER; DELIBERATE PATHS ANNOUNCE. scheduleStep announces plainly when a target is off the box's channel (a production box deliberately given a prerelease is a real deviation that must not be silent) and then proceeds — no gate, 258 stays open. TEST: extend the existing precedent (channel_resolution_git_test.go:178 already extracts RunCheck's body) to assert BOTH discover and RunCheck contain FilterTagsByChannel — one declarative test, both paths pinned, a third discovery site fails the moment it forgets. Engineer building.
---
<!-- COMMENTS:END -->
