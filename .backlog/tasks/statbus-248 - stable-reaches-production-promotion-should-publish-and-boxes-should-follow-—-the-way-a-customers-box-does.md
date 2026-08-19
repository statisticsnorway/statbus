---
id: STATBUS-248
title: >-
  stable-reaches-production: promotion should publish, and boxes should follow —
  the way a customer's box does
status: To Do
assignee: []
created_date: '2026-08-19 07:27'
updated_date: '2026-08-19 07:40'
labels:
  - release
  - ops
  - upgrade
dependencies: []
references:
  - .github/workflows/master-to-production.yaml
  - .github/workflows/production-to-all.yaml
  - cli/internal/upgrade/service.go
  - doc/CLOUD.md
priority: high
type: enhancement
ordinal: 241000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Retiring the deploy buttons removes the only thing that currently pushes a release out to the ordinary installations. Before they go, we need to say what replaces them — and the answer is a policy decision about promotion day, not a missing mechanism.

WHAT GOES WRONG IF THIS IS SKIPPED: the buttons are removed, a release is promoted to stable, and nothing happens to any production box. Somebody notices days later and reaches for a manual command, which is exactly the ad-hoc path the whole sweep exists to eliminate.

WHICH BOXES THIS ENTRY IS ABOUT: the ones with no special release role — **demo and the production slots**. Dev is driven by the release chain and Norway is the human canary; both are governed by STATBUS-247 and are out of scope here.

THE DETAIL — there are two shapes, and they are not equally good.

**Push it out from the release.** Promoting a stable version points every slot's deploy branch at it, the same way STATBUS-247 does for dev. Immediate, observable, one act. But it also means promotion and rollout become the same event, so every installation moves at once and there is no way to stagger.

**Let the boxes follow.** Each box already has an upgrade service that polls for its channel's latest release, registers it, schedules it and installs it — the same discover → register → schedule → execute path a statistical office relies on. Set those slots to the stable channel and promotion simply publishes; the boxes arrive on their own.

**RECOMMENDATION: let the boxes follow.** These are not special infrastructure — they are NSO-shaped installations, and they should behave exactly as a customer's box does, because that is the path we most need to be exercising continuously. It also separates two decisions that should not be welded together: blessing a release, and moving a particular installation onto it. And it needs no new mechanism at all, only the channel each box already reads.

Note this is deliberately a different choice from dev, and the asymmetry is principled rather than inconsistent. Dev is tag-driven because the release chain needs a SYNCHRONOUS verdict — it must know now whether a real box took the candidate. These boxes have no such need: nobody is gating on them, so an autonomous tick is not a delay, it is just how software reaches a machine. Each box still has exactly one source of truth about what it should be running, which is what STATBUS-244 requires.

WHAT MUST BE VERIFIED, not assumed: that each box is on the channel its ROLE requires, and that a promoted release appears in the shape the stable channel filter selects. The verification cannot be "everything is on stable" — Norway must stay on prerelease to remain the human canary, so a sweep that tidied it onto stable would pass a naive check while deleting a release gate. A box on a wrong or default channel looks identical to a box with nothing to do, in either direction.

WHY THAT HELPS: promotion becomes what it claims to be — a statement that a release is fit — and the installations act on it themselves, continuously proving the same path every customer depends on. Nobody has to remember to push anything, and no box's version depends on whether they did.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 A decision is recorded: channel-following installations follow the stable channel (recommended) or promotion pushes to them, with the reasoning on this ticket
- [ ] #2 Every box is verified to be on the channel its ROLE requires — not universally stable. A box on the wrong channel fails this check in either direction, including one quietly moved to stable when its role needs prerelease
- [ ] #3 Norway is explicitly excluded from any stable-channel sweep: it is both a production installation and the human canary (STATBUS-247), and stays on prerelease
- [ ] #4 A promoted release is verified to appear in the shape the stable channel filter actually selects
- [ ] #5 Promoting a stable release results in the channel-following installations — demo and the production slots — converging on it with no human push
- [ ] #6 Each box has exactly one source of truth for what it should run — no path both pushes to it and lets it follow
- [ ] #7 master-to-production and production-to-all can then be removed without leaving a gap
<!-- AC:END -->

## Comments

<!-- COMMENTS:BEGIN -->
author: architect
created: 2026-08-19 07:37
---
SCOPE CARVE-OUT after the King's ruling 4 (three-role canary topology, STATBUS-247). This entry says "production slots follow the stable channel". That phrase now needs a boundary drawn on it, because one box is in both categories.

NORWAY (rune-no) IS BOTH. It is a real production deployment for a statistical office, and under ruling 4 it is also one of the two human-fidelity canaries — offered each candidate, installed by a person. So it must NOT be moved to the stable channel by this entry. It stays on the prerelease channel with a human performing the install, and STATBUS-247 governs it.

THIS IS NOT A NEW EXPOSURE, which I checked rather than assumed: doc/CLOUD.md:769 already authors standalone boxes with UPGRADE_CHANNEL=prerelease, so Norway runs release candidates today. Ruling 4 changes who presses the button there, not what channel it drinks from.

WHY IT MATTERS THAT THIS IS WRITTEN DOWN: an implementer reading "set the production slots to stable" and working from the deployment table would sweep Norway in, and the change would look tidy and correct. It would silently delete half the human-fidelity canary coverage, and nothing would fail — the gate would simply stop having a candidate to find, and the release process would get quieter rather than louder. That is the zero-scope-green shape (doc-033) arriving through a configuration change instead of a check.

SO THE SCOPE OF THIS ENTRY IS: production slots that are NOT canaries. Concretely, dev, demo and no are governed by STATBUS-247 and are out of scope here; everything else that is a live installation is in. AC#2's verification should therefore assert the channel each box is SUPPOSED to be on per its role, not that every box is on stable — a box on the wrong channel for its role is the failure this entry is meant to prevent, in either direction.
---

author: architect
created: 2026-08-19 07:39
---
SCOPE RESTATED under the King's final topology — this supersedes the carve-out in comment #1, which was written when demo was still a canary.

IN SCOPE for this entry (ordinary installations that follow releases on their own): **demo**, plus the production slots. Demo moved here by the King's ruling — dev already answers the does-it-install question, so a second automatic canary would only repeat it. Demo is now a normal box, and its promotion-day behaviour is this entry's question, not STATBUS-247's.

OUT OF SCOPE: **dev**, driven by the release chain; and **Norway**, the single human canary, which stays on the prerelease channel with a person performing each promotion-bound install against an observation card. Both are governed by STATBUS-247.

THE NORWAY WARNING FROM COMMENT #1 STANDS AND IS NOW THE ONLY ONE. Norway is both a real production installation and the human canary, so an implementer reading "set the production slots to stable" and working from the deployment table would sweep it in. That change would look tidy and correct, and nothing would fail — the gate would simply stop finding a candidate to wait on, and the release process would get QUIETER rather than louder. It would delete the entire human-canary role in one config edit. This is the zero-scope-green shape (doc-033) arriving through configuration instead of through a check, which is why it is written down twice.

AC#2 SHOULD THEREFORE ASSERT ROLE-CORRECT CHANNELS, not universal stable: each box on the channel its role requires, with a wrong channel failing in EITHER direction. A box quietly on stable when its role needs prerelease is exactly as broken as the reverse, and considerably harder to notice.
---
<!-- COMMENTS:END -->
