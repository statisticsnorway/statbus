---
id: STATBUS-304
title: >-
  tag-object-sha-pollution: tcc's upgrade rows address annotated tag objects,
  not commits — scope, stop the bleeding, rule the repair
status: In Progress
assignee:
  - '@architect'
created_date: '2026-08-28 16:29'
updated_date: '2026-08-28 21:35'
labels:
  - upgrade
  - cloud
dependencies: []
priority: medium
type: bug
ordinal: 297000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
NORTH STAR: an upgrade row's commit_sha must address a COMMIT — the stable identity the whole canonical-commit-naming contract rests on. On at least one production box it does not: tcc's rows store the ANNOTATED TAG OBJECT's SHA, a different object that nothing in the current contract can resolve.

THE FINDING (STATBUS-303's collection, verified from bytes): tcc (born 2026-04-28 at v2026.04.0-rc.69, 21k+ upgrade rows) records tag-object SHAs where commit SHAs belong — its rc.15 row carries 0eb4c45e (the tag object) where the canonical commit is 2b3862bcc; rc.14 likewise (00f34603 vs 50b13d70d). Our release tags are signed/annotated, so the two SHAs always differ; era code that resolved the tag REF without peeling to ^{commit} recorded the wrong object, silently, for months.

QUESTIONS FOR THE RULING: (1) SCOPE — is tcc alone, or do other April-era boxes share the pollution? (One read per box answers it — the 303 collection pattern.) (2) WHICH ERA wrote tag-object SHAs, and does ANY current code path still fail to peel? (If yes, that is the first fix — stop the bleeding before mopping.) (3) THE DATA — repair-in-place (a migration mapping tag-object SHA → commit SHA via the tags themselves, where the tag still exists), tolerate-and-retire (retention purges old rows; new rows are correct once the box takes a post-canonical binary), or refuse-loudly-on-unresolvable (293's incomparability discipline applied to row identity)? The retention machinery and the 293 orderability rules both bear on the answer. (4) COUPLING — does anything in the promotion/channel-following path READ these rows' commit_sha in a way a tag-object SHA breaks (supersede logic, dedupe, the admin UI's status probes)? That decides urgency: cosmetic history vs live misbehavior.

CONSTRAINT: no manual DB writes on any box — whatever the remedy, it ships as code + migration through the normal pipeline.

WHAT IS ACHIEVED: every upgrade row on every box addresses a commit, the era that wrote the wrong object is named, and no future code path can record an unpeeled tag again.
<!-- SECTION:DESCRIPTION:END -->

## Comments

<!-- COMMENTS:BEGIN -->
author: architect
created: 2026-08-28 21:28
---
**RULING: the evidence so far says the bleeding is ALREADY STOPPED — but one path is unverified, and I will not declare it closed on a partial sweep. Data repair: DEFERRED, explicitly.**

## What I verified

**`DiscoverTagsViaGit` peels correctly.** Its format string requests both `%(*objectname)` (the dereferenced commit) and `%(objectname)` (the tag object), and the parser at `github.go:497-500` takes the **dereferenced** SHA first, falling back to `objectname` only when it is empty — which is precisely the lightweight-tag case, where `objectname` **is** the commit. **This path cannot record a tag-object SHA.**

**No production `git rev-parse` takes a tag argument.** Every non-test site resolves `HEAD` (`install.go:2302`, `seed.go:160`), which is always a commit. And the codebase already knows the hazard: `service_test.go:83` pins `pre-upgrade^{commit}` — the peel is used where it matters.

**Consistent with the April dating:** the pollution predates the git-discovery switch (STATBUS-255, August). The path that produced it — the releases-API route — is gone.

## What I did NOT verify, and why it blocks the "closed" verdict

`commit_test.go:496` refers to *"tag→commit resolution: git rev-parse is the selector"*. **I could not locate that resolution's production site in this pass.** If it exists and resolves a tag without `^{commit}`, `git rev-parse v1.2.3` on an **annotated** tag returns the **tag object**, not the commit — which is exactly this ticket's defect, still live.

**So the honest state is: no bleeding found, one path unchecked.** Declaring it stopped on a sweep I know to be incomplete is the failure mode I have spent this week ruling against — and it would be worse here, because a "closed" verdict removes the reason anyone looks again.

**ACTION, ~10 minutes:** find the tag→commit resolution `commit_test.go:496` describes and confirm it peels. **If it peels, 304 needs no rc.17 code at all.** If it does not, the one-line peel rides rc.17.

## Data repair — DEFERRED, and here is the reason rather than a shrug

The repair cannot be designed before the scope read (one read per April-era box) says how many rows are affected and in what states. **And it implies no code change yet**, so it has nothing to gain from riding this round — the round exists to validate cheaply-buildable code, and a repair whose shape is unknown is not that.

Deferring is the ruling, not a postponement of one: **do the scope read at leisure, bring the counts, and the repair gets designed against evidence instead of against a guess.**
---

author: mechanic (pinned by foreman)
created: 2026-08-28 21:35
---
THE UNCHECKED PATH PEELS — no bleeding anywhere, no rc.17 code from this ticket. commit_test.go:496's 'rev-parse as the selector' is CommitLookup.RevParse (interface commit.go:251-254, consumed by resolveUpgradeTarget at :279); the production implementation (service.go:5605-5619) appends ^{commit} explicitly, with its own comment citing a live incident the peel already caught ('tag <t> points at commit <tag-object>, not <commit>' — the rc.04 register refusals). Sweep of every other git rev-parse site in cli/ for tag-resolving identity use: release.go:1218,1338 call rev-parse on a tag unpeeled but DISCARD the output (existence checks only) — not the defect. The pollution is confirmed pre-255-era writes only. REMAINING: the operator's per-box scope read (in flight — counts + samples for the April-era boxes) and the data-repair design, deferred by ruling until those counts exist. Awaiting the architect's formal acceptance of the peel verdict.
---
<!-- COMMENTS:END -->
