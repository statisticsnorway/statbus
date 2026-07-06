---
id: STATBUS-133
title: >-
  test-run-serialization: replace the hook's who-is-asking identity check with
  an flock in the test runner
status: To Do
assignee: []
created_date: '2026-07-04 12:15'
updated_date: '2026-07-06 14:24'
labels:
  - team-hooks
  - tooling
  - operator-ux
dependencies: []
references:
  - .claude/hooks/restrict-agent-spawn.sh
  - .claude/hooks/require-bash-background.sh
  - .claude/hooks/test-restrict-agent-spawn.sh
priority: medium
ordinal: 134000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
NORTH STAR: test results must be trustworthy — two test runs must never share the development database's templates at the same time, because concurrent runs corrupt each other and produce failures that are not real (violating "there are no flaky tests").

KING RULING (2026-07-06): the original mechanism — a hook that identifies WHO is running the command from the session's transcript and only admits "the tester" — was overengineering. Identity was a proxy: one designated runner ⇒ serialized runs. Serialize DIRECTLY instead: a kernel flock taken by the test runner itself. Simpler, nothing to bootstrap after a clear/crash/compaction (the transcript-identity approach broke on all three: a fresh tester was refused, and the post-compaction foreman was unidentifiable), and the lock self-releases on process death — the same property the upgrade system already trusts flock for (tmp/upgrade-in-progress.json).

FIX SHAPE:
1. dev.sh test entrypoints (the paths that touch shared pg_regress templates: test, create-db and friends) take an exclusive flock on a well-known lockfile (e.g. tmp/.test-run.lock) before touching templates; on contention, fail loudly and actionably ("another test run is in progress, pid/started-at ...") — never queue silently, never proceed.
2. RETIRE the hook's rule 4 (the ./dev.sh test identity gate in .claude/hooks/restrict-agent-spawn.sh) — the flock supersedes it. "The tester runs the tests" remains a TEAM CONVENTION for coordination and reporting, not machine-enforced.
3. While in the hook: fix the content false-positive (it pattern-matches './dev.sh test' inside heredoc/file CONTENT being written, not just executed commands — it blocked authoring a launcher script whose text mentioned the command).
4. Update .claude/team docs + test-restrict-agent-spawn.sh cases to the new shape (drop rule-4 identity cases, keep the other rules' coverage).

VERIFICATION: unit-style — two concurrent invocations, second fails loudly with the holder named; single invocation unaffected; lock vanishes with a killed holder.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Two concurrent test runs are impossible: the second fails loudly naming the holder (no silent queueing, no silent proceed)
- [ ] #2 A freshly started agent (post-clear/crash) can run tests on first attempt — no identity bootstrap of any kind remains on the test path
- [ ] #3 The hook no longer matches test commands inside file content being written; a regression case is added to its test file
<!-- AC:END -->

## Comments

<!-- COMMENTS:BEGIN -->
author: foreman
created: 2026-07-06 14:24
---
RE-SCOPED per the King (2026-07-06): identity-proof mechanism rejected as overengineering; serialization via flock in the test runner is the ruling. Foreman analysis concurs: the rule's stated WHY was concurrent-run corruption — a concurrency problem; identity was a proxy for serialization, and the direct primitive (flock, self-releasing on death) is strictly simpler and crash-proof. Old description's fix candidates (identity file / first-occurrence match / bounded grace) are all superseded.
---
<!-- COMMENTS:END -->
