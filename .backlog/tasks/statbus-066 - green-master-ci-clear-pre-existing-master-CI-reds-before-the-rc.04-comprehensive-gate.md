---
id: STATBUS-066
title: >-
  green-master-ci: clear pre-existing master CI reds before the rc.04
  comprehensive gate
status: In Progress
assignee: []
created_date: '2026-06-16 14:06'
labels:
  - ci
  - test-hermeticity
  - rc.04
  - foundational
dependencies: []
priority: high
ordinal: 66000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Master CI was RED on pre-existing failures (on the prior tip c175ef1a8, independent of the rc.04 batch) — a release cannot be cut from red master. Two reds found + cleared:

1. Go Test — cli/cmd/release_verify_test.go's tagAnnotated/tagAt created annotated git tags WITHOUT setting an identity env (unlike the run/commitAt helpers), so they fell back to ambient global git config: passed locally (developer identity leaks in), exit-128 ("no email ... auto-detection disabled") on hermetic CI runners. A host-config-leak / test-hermeticity bug. FIX (committed 08f4e5d9c): give the throwaway repo a hermetic identity in makeRepo (user.name/user.email). Reproduced the exact CI 128 locally under a stripped env (env -i + user.useConfigOnly=true), RED→GREEN confirmed; normal run unaffected.

2. Fast Tests + pg_regress — test 002_generate_mermaid_er_diagram. The rc.04 commit 23c5c33f1 added public.upgrade.from_commit_sha (migration 20260616104500) and regenerated database.types.ts + doc/db/table/public_upgrade.md, but MISSED the ER-diagram baseline. Schema correct; snapshot one line stale. FIX (committed 537c56b48): regenerate the 002 expected (+ `text from_commit_sha`), gated on the exact one-line diff (one line, one file).

Both pushed (537c56b48 on master). Fresh CI run confirms green (pg_regress confirmation was pending a transient GitHub API outage at push time; the re-run settles it). Close when CI is confirmed green.
<!-- SECTION:DESCRIPTION:END -->
