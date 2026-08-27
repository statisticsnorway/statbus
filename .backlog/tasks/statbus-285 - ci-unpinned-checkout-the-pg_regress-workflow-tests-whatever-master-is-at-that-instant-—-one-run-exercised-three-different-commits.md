---
id: STATBUS-285
title: >-
  ci-unpinned-checkout: the pg_regress workflow tests whatever master is at that
  instant — one run exercised three different commits
status: To Do
assignee: []
created_date: '2026-08-27 17:11'
updated_date: '2026-08-27 18:42'
labels:
  - ci
  - testing
dependencies: []
priority: high
type: bug
ordinal: 278000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Found by the mechanic during read-only evidence pulling (2026-08-27, run 33096555771): a single pg_regress workflow run on the self-hosted niue runner carries THREE distinct commits — the run's API metadata headSha (620cc7f0b), the commit the outer actions/checkout landed on (7cc250b2), and the commit the inner "Run tests on remote server" step's own `git checkout` re-synced to moments later (061b63d01) — because master advanced between those steps and nothing pins the triggering SHA. All three were verified on the master line, so the run was not wrong, but "this run's verdict is about commit X" has no single true X, and the SHA actually exercised by the tests is only discoverable by reading the inner log.

Why it matters: the fast-test stamp (tmp/fast-test-passed-sha) and the release preflight's CI-green checks treat a run's conclusion as evidence about a named commit — the whole canonical-commit-naming doctrine. An unpinned checkout quietly weakens that to "some commit at-or-after the trigger". On a busy evening (tonight: four board commits in an hour) the drift window is real and observed.

Fix shape: both checkout sites in the pg_regress workflow (and any sibling workflow with the same pattern — audit .github/workflows/) must check out `github.sha` (the triggering commit), never the branch ref. The inner remote test step must receive and check out that same SHA explicitly. Then a run's conclusion is evidence about exactly one named commit, matching what the stamp and preflight already assume it means.

WHAT IS ACHIEVED: every CI verdict names exactly one commit, and the stamps and release gates built on those verdicts inherit that precision instead of a silent at-or-after.
<!-- SECTION:DESCRIPTION:END -->

## Comments

<!-- COMMENTS:BEGIN -->
author: architect (pinned by foreman)
created: 2026-08-27 18:42
---
ESCALATED from drift-oddity to GATE INTEGRITY (architect, 2026-08-27 evening, during the 288 landing): every branch of the release preflight's CI-escape family consumes head_sha-keyed evidence via checkWorkflowAt — and NONE of them can be sounder than that key. Second observed instance the same evening: minting run 33099747588's nominal headSha was a47aa3c0b while its own checkout log shows 'HEAD is now at b319ae4be' — a green ATTRIBUTED to one commit that EXECUTED at another. That is the zero-scope-green class at its most dangerous: evidence about HEAD produced somewhere that is not HEAD. It applies to BOTH escape oracles equally (fast-tests and pg_regress), so it does not disturb the 288 split — but it qualifies every claim of 'green at HEAD' with a known attribution hazard until fixed. Tonight's cut was safe because the substance was verified at the EXERCISED commit (89/89 incl 095/096, source version 20260827163000). Priority raised accordingly: this ticket is now the foundation the whole escape family rests on, first in queue after the release-candidate work settles.
---
<!-- COMMENTS:END -->
