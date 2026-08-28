---
id: STATBUS-304
title: >-
  tag-object-sha-pollution: tcc's upgrade rows address annotated tag objects,
  not commits — scope, stop the bleeding, rule the repair
status: In Progress
assignee:
  - '@architect'
created_date: '2026-08-28 16:29'
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
