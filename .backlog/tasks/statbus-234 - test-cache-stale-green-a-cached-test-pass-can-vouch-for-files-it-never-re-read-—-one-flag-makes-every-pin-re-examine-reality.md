---
id: STATBUS-234
title: >-
  test-cache-stale-green: a cached test pass can vouch for files it never
  re-read — one flag makes every pin re-examine reality
status: To Do
assignee:
  - mechanic
created_date: '2026-08-18 15:38'
labels:
  - ci
  - quality-gate
  - tooling
dependencies: []
references:
  - .github/workflows/go-test.yaml
  - dev.sh
  - .claude/team/engineer.md
priority: medium
type: bug
ordinal: 234000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Several of our most important tests are pins: they read files OUTSIDE the Go module — workflow YAML, the exempt list, shell scripts — and assert facts about them. Go's test cache does not track those outside files, so a cached "ok" can vouch for content that has since changed.

WHAT THE EVIDENCE SHOWS (engineer, 2026-08-18, demonstrated not reasoned): prime the cache with a green run, append an entry to ops/release/ci-exempt-paths.txt, re-run without -count=1 — "ok (cached)", a green that examined nothing current. The seventh instance of doc-033's class: a check reporting a verdict over something it never read. Applies to the whole pin family (arc-path pin, run.sh marker pin, images-never-rides pin, trigger pins, exempt-list equality pin), not just the newest. CI exposure is PLAUSIBLE but unconfirmed: go-test.yaml runs plain go test ./... and setup-go@v5 caches by default — verify, don't inherit, per the house rule.

THE FIX: -count=1 on the CI go test invocation (one flag in go-test.yaml), the same in dev.sh's chain if it runs go test anywhere, and the role docs' freeze chain already says -count=1 informally — make it uniform. Verify the CI-exposure question empirically while in there (does a cached pass actually survive across CI runs with setup-go's cache?) and record the answer either way.

WHAT IS ACHIEVED: a pin's green goes back to meaning "I read the file today" — the property the entire pin strategy stands on.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 CI's go test runs with -count=1 (and dev.sh's chain where applicable); the change is commented with the outside-module cache gap
- [ ] #2 The CI-exposure question answered empirically and recorded: could a cached pass have crossed CI runs before this fix
- [ ] #3 Role docs' chain wording names -count=1 uniformly
<!-- AC:END -->
