---
id: STATBUS-404
title: Running the one install command again converges an unchanged box
status: To Do
assignee: []
created_date: '2026-09-24 15:35'
labels:
  - install
  - idempotency
dependencies: []
priority: high
type: bug
ordinal: 357000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Running the one install command on a green unchanged box leaves settings, certificates, images, and services settled. Each step reports OK unless it applies a real change. Image detection reads the fields produced by the installed container tooling.

## Evidence, 2026-09-24

Primary records: `/Users/jhf/ssb/statbus/tmp/finland-transcript-2-actual.txt`, `/Users/jhf/ssb/statbus/tmp/finland-chat-3.txt`, `/Users/jhf/ssb/statbus/tmp/finland-answers-4.txt`, `/Users/jhf/ssb/statbus/tmp/installer-message-audit.md`, `/Users/jhf/ssb/statbus/tmp/setup-connection-map.md`, and `/Users/jhf/ssb/.jcode/scratch/rest-loop.md` (as applicable). Proposed behavior below is not an observation.

Finland reruns regenerated settings and pulled every image. The image check parsed a `Container` field while actual JSON uses `ContainerName`, so present images looked absent.

## Proving scenario

Extend `0-happy-install` to run the one install command a second time. Every step reports OK and the transcript contains settled image status. Unit coverage feeds real version 2 and version 5 JSON with `ContainerName` to image detection.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 A second run on a green unchanged box reports OK for every step.
- [ ] #2 The second run preserves settled settings, certificates, images, and services.
- [ ] #3 Image detection recognizes real tool output that uses the `ContainerName` field.
- [ ] #4 A changed input causes only the affected steps to report RUNNING and apply work.
<!-- AC:END -->
