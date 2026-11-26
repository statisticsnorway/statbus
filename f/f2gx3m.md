---
id: f2gx3m
title: "Counting issue in jo.statbus.org"
state: todo
type: feature
priority: ""
assignee: []
labels: []
group: ""
rank: "zzzzzzzzzzzx"
created: 2026-11-26
updated: 2026-11-26
---

## Goal
Counting issue in jo.statbus.org

## Depends on

## Acceptance
- [ ] Verify Counting issue in jo.statbus.org

## Requests
- 2026-11-26T21:15 request 1 by jhf:
  The issue here is twofold. One, if you look at the count in the image, you will see that they don't add up. And the question is why. And I think it is because something is valid that isn't born, and then thus the counting has to have a mistake. We have to fix the test, have it fail, and then the counting will be correct. However, I think we can catch it with a validation. The team asked for birth date has to be after valid has to be before valid from. That is invalid. But I think birth date can't be more than a year in the future from valid from. Meaning if you are valid from a year, then you have to be born in the same year, not a later year, and we shall do it during validation. All of this must be played by me when this ticket is due. It is not yet.

## Notes

file:paste-1540.png (169473 bytes, sha256:f4f591fe) pasted from the clipboard in hug tui


## History
- 2026-11-26T21:15 request 1 by jhf
- 2026-11-26T21:15 request 1 delivered to rabbit (session_rabbit_1788255452439_e2c96135756f0328)
