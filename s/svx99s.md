---
id: svx99s
title: "A unit's photo keeps the whole picture, scaled to at most 800 px"
state: "doing"
type: feature
priority: ""
assignee: ["rabbit"]
labels: []
group: ""
rank: "zzzy"
created: 2026-11-19
updated: 2026-11-19
doing_since: "2026-11-19T19:06"
stage: "active"
model: "claude-opus-5-5"
branch: "master"
worktree: "/Users/jhf/ssb/statbus_test"
---

## Goal
A unit's photo is stored whole, scaled so its longest side is at most 800 px, as JPEG under the database's 256 KB limit, and the full photo can be opened from the unit page.

## Purpose
Owner 2026-11-19 18:05: the centred square crop of w79490 cut off up to an eighth of each side of a landscape photo, so a sign or house number near the edge was lost without the user noticing. No cropper: the person taking the photo already framed it.

## Principle
Keep what the user photographed; only make it small enough. The database limit (256 KB) and cleanup from w79490 stay as they are.

## Relevant details
app/src/lib/unit-photo.ts: fitWithin(width,height,800) replaces centreSquareCrop; JPEG quality steps down from 0.85 until the file is under 256 KB. The thumbnail stays a 96 px square (object-cover) and links to the full photo.

## Depends on

## Acceptance
- [ ] Unit test: a 4032x3024 photo is scaled to 800x600, a 3024x4032 to 600x800, a 640x480 stays 640x480
- [ ] In the app on the test slot, a 10 MB 4032x3024 phone photo is stored as an 800x600 JPEG under 256 KB, and the unit page's thumbnail opens the whole photo

## Notes


## History
- 2026-11-19T19:06 todo -> doing/active (take)
