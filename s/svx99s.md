---
id: svx99s
title: "A unit's photo keeps the whole picture, scaled to at most 800 px"
state: "done"
type: feature
priority: ""
assignee: ["rabbit"]
labels: []
group: ""
rank: "zzzy"
created: 2026-11-19
updated: 2026-11-19
model: "claude-opus-5-5"
branch: "master"
worktree: "/Users/jhf/ssb/statbus_test"
done_at: "2026-11-19T19:29"
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
- [x] Unit test: a 4032x3024 photo is scaled to 800x600, a 3024x4032 to 600x800, a 640x480 stays 640x480
- [x] In the app on the test slot, a 10 MB 4032x3024 phone photo is stored as an 800x600 JPEG under 256 KB, and the unit page's thumbnail opens the whole photo

## Notes


2026-11-19 18:10 (Rabbit) 98dc51f6c on master. Unit test RED tmp/svx99s-red.log (fitWithin missing) -> GREEN tmp/svx99s-green.log (4032x3024->800x600, 3024x4032->600x800, 640x480 kept). Real app on test.statbus.org:3031 (tmp/svx99s-photo-walk.log): a 10.6 MB 4032x3024 JPEG of random noise (worst case for JPEG) stored as 800x600 JPEG, 252,721 bytes, under the 256 KB limit through the quality step-down; served back as 800x600; thumbnail links to /rest/rpc/image_data?id=17; replace leaves 1 photo, remove leaves 0; no page errors. LU 29 restored to no photo. Tests 114 and 407 pass.
landed 98dc51f on master 2026-11-19: photos: a unit's photo keeps the whole picture, scaled to at most 800 px…
2026-11-19 18:29 (Rabbit) CI all green on 98dc51f6c: Fast Tests, Go Test, app build & lint, Harness Selftest, Images, Push on master.
Reflection (open, 2026-11-19, rabbit): Owner noticed the square crop could lose part of the picture; agreed on no cropper, whole photo scaled to 800 px. Testing with random noise (JPEG's worst case) showed the quality step-down is needed: it landed at 247 KB, just under the limit.
## History
- 2026-11-19T19:06 todo -> doing/active (take)
- 2026-11-19T19:29 doing/active -> done (done); was doing_since: 2026-11-19T19:06
