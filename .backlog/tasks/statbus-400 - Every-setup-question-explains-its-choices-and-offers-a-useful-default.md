---
id: STATBUS-400
title: Every setup question explains its choices and offers a useful default
status: Done
assignee: []
created_date: '2026-09-24 15:35'
updated_date: '2026-10-08 15:17'
labels:
  - release-bug
  - install
  - ux
dependencies: []
priority: high
type: bug
ordinal: 353000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Interactive setup uses plain words and one-line explanations, and every question offers a useful default. The mode question explains all three modes and suggests standalone (owner decision, STATBUS-465; the earlier 'private laptop defaults to development' was reversed). The domain starts empty. A standalone or private installation asks for the country name and country code, with defaults from the domain or the host time zone (STATBUS-466). Development may invent a name and code. Rerun revision of persisted answers is STATBUS-412.

## Evidence, 2026-09-24
The Finland prompt offered internal deployment labels and defaulted to standalone plus statbus.nso.eu (/Users/jhf/ssb/statbus/tmp/finland-transcript-actual.txt:46-52).
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 `new: cli/internal/installinput/config_test.go::TestSetupChoiceExplanationsAndDefaults` asserts every choice's exact plain-language explanation, an empty fresh domain, and domain-derived site code.
- [x] #2 Every setup question (mode, domain, name, code) explains itself and offers a useful default in each mode, observed with the real ./sb install on a PTY (STATBUS-466 notes); a real-guest scenario is STATBUS-474, rerun revision is STATBUS-412 AC1
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Audit after v2026.09.3 (2026-09-29): v2026.09.3 (bda0df07b, 0a166d25e): plain choice explanations, empty domain, domain-derived code. AC1 is green in Go Test. Remaining: 0-interactive-setup-choices.sh (AC2/AC3) and the rerun revision via STATBUS-412.

## 2026-10-08: closed with 3a87b058e (STATBUS-466)

What 400 asks, "every setup question explains its choices and offers a useful default", now holds for every question in every mode (observed with the real ./sb install on a PTY; the transcripts are in STATBUS-466's notes and tmp/statbus-466-observed/interactive-prompts.txt):
- Mode: all three choices explained, default standalone (STATBUS-465). An unknown answer is now re-asked instead of written.
- Domain: explained, empty by default (AC1).
- Name: standalone/private asks "Which country does this installation serve?" with a default from the domain or host time zone and the reason shown, else entry is required. Development asks "Display name [StatBus]" and says it may invent one.
- Code: standalone/private suggests the chosen country's ISO code and warns, without blocking, on a non-country code. Development derives it from the domain, or local, and an unusable label no longer aborts the install.

AC1 changed with this work: TestSetupChoiceExplanationsAndDefaults now asserts the country explanations and the domain-derived country name/code (statbus.stat.fi -> Finland/fi). RED at d47b17abf (compile-only shim, host jhf's Mac, Go only, no database): `defaults: mode "standalone" domain "" name "" code ""`. GREEN at 3a87b058e. CI Go Test 37798000729 success.

AC2 and AC3 restated (removed here, not hidden):
- AC2 (detect a private laptop and default to development) was reversed by the owner decision in STATBUS-465 (054611d1d: always suggest standalone). Its real intent, a real-guest scenario that walks the questions at their defaults and finishes an install, is filed as STATBUS-474.
- AC3 (rerun revises persisted answers) is word for word STATBUS-412 AC1 (0-interactive-rerun-answers.sh). 412 owns it, so 400 no longer depends on 412.
<!-- SECTION:NOTES:END -->

## Status 2026-09-24

**In Progress.** `bda0df07b`, `0a166d25e`, `373d15fc3`: `cli/internal/installinput/config.go` and `config_test.go` explain choices and select host-appropriate defaults (#1 partly). `0-interactive-setup-choices.sh` does not exist, leaving #2-3 not met. **Remaining:** prove a private laptop defaults to local mode, then prove a persisted answer can be revised on rerun and retained.

Baseline: `origin/master` at `373d15fc3`. Criterion disposition and remaining positive targets are above; the acceptance criteria below remain authoritative. An authored but unrun VM scenario is **proof pending**, not met.

## Comments

<!-- COMMENTS:BEGIN -->
created: 2026-10-08 14:27
---
Takeover review (2026-10-08) against the uncommitted STATBUS-466 WIP. AC1 was already green (v2026.09.3). The WIP adds country-name and country-code questions for standalone, but it leaves the country name with NO default and breaks AC1's own test (TestSetupChoiceExplanationsAndDefaults fails: the standalone code question no longer goes through the old path). AC2 as written ('detects a private laptop, presents local development as the default') is CONTRADICTED by the owner decision in STATBUS-465 (commit 054611d1d: always suggest standalone, battery heuristic removed), so it cannot be met and must be restated. AC3 (rerun revision) is STATBUS-412's own scenario (412 AC1 0-interactive-rerun-answers.sh), on which 400 depends. Remaining for 400 here: every question (mode, domain, name, code) explains its choices and offers a useful default in both modes, with invalid answers re-asked rather than aborting the install.
---
<!-- COMMENTS:END -->
