---
id: STATBUS-400
title: Every setup question explains its choices and offers a useful default
status: In Progress
assignee: []
created_date: '2026-09-24 15:35'
updated_date: '2026-09-29 08:04'
labels:
  - release-bug
  - install
  - ux
dependencies:
  - STATBUS-412
priority: high
type: bug
ordinal: 353000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Interactive setup uses plain words and one-line explanations. On a private laptop, the recommended default is local development rather than a public server. The domain starts empty, site code defaults from the chosen domain's first label, and a rerun presents persisted values as defaults while allowing revision through STATBUS-412.

## Evidence, 2026-09-24

The Finland prompt offered internal deployment labels and defaulted to standalone plus `statbus.nso.eu` (`/Users/jhf/ssb/statbus/tmp/finland-transcript-actual.txt:46-52`). Current hardcoded defaults are in `cli/internal/installinput/config.go:31-33` at master `7a9cf707e`. Detecting a private-laptop situation and recommending local development is target behavior.
<!-- SECTION:DESCRIPTION:END -->

## Status 2026-09-24

**In Progress.** `bda0df07b`, `0a166d25e`, `373d15fc3`: `cli/internal/installinput/config.go` and `config_test.go` explain choices and select host-appropriate defaults (#1 partly). `0-interactive-setup-choices.sh` does not exist, leaving #2-3 not met. **Remaining:** prove a private laptop defaults to local mode, then prove a persisted answer can be revised on rerun and retained.

Baseline: `origin/master` at `373d15fc3`. Criterion disposition and remaining positive targets are above; the acceptance criteria below remain authoritative. An authored but unrun VM scenario is **proof pending**, not met.

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 `new: cli/internal/installinput/config_test.go::TestSetupChoiceExplanationsAndDefaults` asserts every choice's exact plain-language explanation, an empty fresh domain, and domain-derived site code.
- [ ] #2 `new: test/install-recovery/scenarios/0-interactive-setup-choices.sh` detects a private laptop, presents local development as the default, accepts it, and completes the setup flow.
- [ ] #3 `new: test/install-recovery/scenarios/0-interactive-setup-choices.sh` reruns setup, observes persisted values as defaults, changes one value through STATBUS-412, and observes the revised value on the next rerun.
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Audit after v2026.09.3 (2026-09-29): v2026.09.3 (bda0df07b, 0a166d25e): plain choice explanations, empty domain, domain-derived code. AC1 is green in Go Test. Remaining: 0-interactive-setup-choices.sh (AC2/AC3) and the rerun revision via STATBUS-412.
<!-- SECTION:NOTES:END -->
