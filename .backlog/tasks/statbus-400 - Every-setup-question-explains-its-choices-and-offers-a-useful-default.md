---
id: STATBUS-400
title: Every setup question explains its choices and offers a useful default
status: To Do
assignee: []
created_date: '2026-09-24 15:35'
labels:
  - install
  - ux
dependencies: []
priority: high
type: bug
ordinal: 353000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Interactive installation questions use plain words, explain each choice in one line, and offer defaults derived from the computer and domain. The installation type question explains public server, server behind an existing web gateway, and local development without exposing internal component names. The site code defaults from the first domain label, and the domain starts empty.

## Evidence, 2026-09-24

Primary records: `/Users/jhf/ssb/statbus/tmp/finland-transcript-2-actual.txt`, `/Users/jhf/ssb/statbus/tmp/finland-chat-3.txt`, `/Users/jhf/ssb/statbus/tmp/finland-answers-4.txt`, `/Users/jhf/ssb/statbus/tmp/installer-message-audit.md`, `/Users/jhf/ssb/statbus/tmp/setup-connection-map.md`, and `/Users/jhf/ssb/.jcode/scratch/rest-loop.md` (as applicable). Proposed behavior below is not an observation.

The Finland operator selected a public-server installation for a private laptop name. Existing prompts used internal deployment labels and offered `statbus.nso.eu` as a domain placeholder.

## Proving scenario

Unit tests cover prompt text and defaults. A terminal-driven fresh-install scenario records the question flow and selects the recommended choice for a private laptop.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Each interactive question explains every choice in one plain-language line.
- [ ] #2 The recommended installation choice fits the detected network situation.
- [ ] #3 The site code defaults from the first label of the chosen domain.
- [ ] #4 The domain question begins empty and accepts the operator chosen name.
<!-- AC:END -->

## Review correction 2026-09-24

Current hardcoded defaults are `cli/internal/installinput/config.go:31-33`; attach the exact Finland prompt lines to quoted wording. Add **new** `test/install-recovery/scenarios/0-interactive-setup-choices.sh`, asserting exact plain-language choices and the recommended private-laptop default. A rerun presents existing values as defaults and allows revision consistently with STATBUS-412.
