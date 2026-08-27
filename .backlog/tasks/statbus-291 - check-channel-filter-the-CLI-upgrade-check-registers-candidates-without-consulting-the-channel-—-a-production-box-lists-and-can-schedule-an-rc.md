---
id: STATBUS-291
title: >-
  check-channel-filter: the CLI upgrade check registers candidates without
  consulting the channel — a production box lists and can schedule an rc
status: Done
assignee:
  - '@engineer'
created_date: '2026-08-27 20:08'
updated_date: '2026-08-27 20:20'
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

author: architect (pinned by foreman)
created: 2026-08-27 20:15
---
LANDING VERDICT: AMEND then LAND. MUST-FIX: the all-paths test iterates a HARDCODED two-name list while its own comment promises 'a third path fails the moment it forgets' — it would not; the literal never examines an unlisted path. The exact defect class this evening has orbited (a check reporting on what it never examined), aggravated because the comment actively teaches the next author the property is enforced. Fix: DERIVE the enumeration — functions whose bodies call DiscoverTagsViaGit must also call FilterTagsByChannel; a third discoverer is then automatically in scope. Acceptable fallback only if derivation is genuinely awkward: an honest two-paths comment; the literal-under-totality-promise pairing must not survive. THREE NON-BLOCKING NOTES: (1) the announce cannot fire for a bare-SHA target — CI's dev door (upgrade apply <40hex>) schedules off-channel commits silently; defensible (a commit has no channel) but must be SAID at the line, or resolved to its tag for the announce; (2) the zero-match early return skips runOneShot's service poke — and on ua (all tags rc, channel stable) this is now the DEFAULT path on every check, not an edge case: decide with evidence whether the poke matters for registered rows; (3) the must-not-refuse arm matches only one error phrasing — kept but not counted as protection. PRAISED: TagMatchesChannel extraction semantics verified identical incl. unknown-channel and retired-edge cases; the placement comment earns its keep at the tempting line; the none-matching message is the difference between correct behavior and a phantom-failure hunt.
---

author: foreman
created: 2026-08-27 20:19
---
LANDED at a4ac7ca81 (220 insertions across 3 files; foreman-verified uncached: internal/upgrade ok 11.4s, cmd ok 17.3s, vet clean) on the architect's standing AMEND-then-LAND with his prescribed fix implemented exactly and exceeded: the all-paths test now DERIVES its scope from source (functionsCalling scans for every function invoking DiscoverTagsViaGit; each must call FilterTagsByChannel), carries a minimum-count honesty guard (a scan finding fewer than the two known discoverers FAILS — a broken regex cannot become a zero-scope green), and was PROVEN on a synthetic filter-forgetting third discoverer caught by name — the comment's promise demonstrated, not asserted. Note dispositions, all evidence-based: (1) bare-SHA silence SAID at the line — channels are defined over tag shape, an untagged commit has none, and resolving a commit to one-of-possibly-several tags would guess, a poor basis for a notice whose value is stating a fact; CI's dev commit-door correctly stays silent as a distinct deliberate mechanism; (2) the zero-match early return is CORRECT with evidence — runOneShot (service.go:4779-4792) is only a DB connection lifecycle; the sole poke is NOTIFY upgrade_check, already conditional on registered>0, so it could never fire on a zero-match; written at the line including the ua-default-path scale; (3) the refusal-arm narrowness accepted and recorded as non-load-bearing tripwire. Rides the next candidate; Ukraine's spurious rc.11 'available' row from tonight's pre-fix check remains registered — harmless (schedule now announces, the eventual stable outranks it by CalVer) and dies naturally at the next upgrade.
---

author: architect (pinned by foreman)
created: 2026-08-27 20:20
---
POST-LANDING READ (a4ac7ca81): SOUND, closed from the architect's side. The enumeration is genuinely derived (a third discoverer is caught the day it is written); the minimum-count guard is BETTER than asked — the zero-scope-green defence applied to the test's own instrument, exactly where it was missing; the needle carrying its open paren matches call sites, not prose; the zero-match disposition is correct on the merits. TWO SMALL FOLLOW-UPS, fold into whatever next touches channel_resolution_git_test.go — neither worth its own commit: (1) the scan reads service.go ONLY while the comment says 'every function' — either add the clause 'in service.go' (honest) or scan the package directory (proper); the unqualified sentence is the same shape that misled last time, one level milder. (2) functionsCalling is a line-anchored approximation (spans ^func to next ^func, swallows inter-function comments), erring toward loud false positives — safe direction, but say so in one line or the next author will read it as AST-accurate and build on it. THE REUSABLE SHAPE from this ticket, named for the next site: AUTOMATIC PATHS FILTER, DELIBERATE PATHS ANNOUNCE — it will decide the next site without another ruling.
---
<!-- COMMENTS:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
The release topology's central promise — production boxes are never offered software the channel didn't bless — now holds at every surface. The CLI's upgrade check filters discovery through the same FilterTagsByChannel as the service path (placed in RunCheck, deliberately NOT the shared upsertCandidate, so the King's named-target deliberate-deployment verb stays open); a deliberately scheduled off-channel tag is announced plainly and proceeds (the ruling's named rule: automatic paths filter, deliberate paths announce); one extracted definition of on-channel serves filter and announce so they cannot drift; and the guarding test derives its scope from source with a minimum-count honesty guard, proven against a synthetic third discoverer. Found live on Ukraine hours after its discovery came alive; the gap predated STATBUS-255 (ported faithfully, input widened) and had been masked fleet-wide only because nobody ran the CLI check on a production box. Landed at a4ac7ca81.
<!-- SECTION:FINAL_SUMMARY:END -->
