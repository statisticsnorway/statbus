---
id: STATBUS-133
title: >-
  test-run-serialization: replace the hook's who-is-asking identity check with
  an flock in the test runner
status: In Progress
assignee:
  - engineer
created_date: '2026-07-04 12:15'
updated_date: '2026-07-06 15:26'
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
- [x] #1 Two concurrent test runs are impossible: the second fails loudly naming the holder (no silent queueing, no silent proceed)
- [x] #2 A freshly started agent (post-clear/crash) can run tests on first attempt — no identity bootstrap of any kind remains on the test path
- [x] #3 The hook no longer matches test commands inside file content being written; a regression case is added to its test file
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
ENGINEER IMPLEMENTATION (verified, NOT yet committed — awaiting foreman review):

PORTABILITY DECISION (settled by evidence on this machine): `command -v flock` → exit 1 (flock(1) ABSENT); bash 3.2.57. So the `exec 9>lock; flock -n 9` idiom is unavailable, as is the syscall.Flock the Go upgrade code uses. Chosen mechanism: atomic `mkdir` lock + pidfile (pid, started-at, action) + stale detection via `kill -0`. mkdir is atomic on every POSIX fs; the pidfile names the holder for the loud error; kill -0 gives the SAME crash-safety as a kernel flock (a SIGKILL'd holder whose EXIT trap never ran is reclaimed by the next run) without a kernel lock. Re-entrancy for nested `./dev.sh` calls via an exported STATBUS_TEST_LOCK_HELD env var (outermost process owns + releases; children pass through). Rejected perl-flock-via-inherited-fd: works but is obscure/hard to introspect, and would STILL need a pidfile for the holder message.

FILES:
- dev.sh: added acquire_test_run_lock/release_test_run_lock helpers + a case gating acquisition on the template-touching entrypoints (test, test-isolated, migrate-and-test, create-db, create-db-structure, reset-db-structure, delete-db, delete-db-structure, recreate-database, create-test-template, create-seed, delete-seed, recreate-seed, seed-clone, clean-test-databases). Chained release into the two entrypoints that overwrite the EXIT trap (cleanup_shared_test_db, cleanup_test_db); release is idempotent (no-op unless _TEST_LOCK_OWNED). continous-integration-test intentionally excluded (isolated runner; drives the above as children which each lock).
- restrict-agent-spawn.sh: RETIRED rule 4 (test identity gate); renumbered git-ops→Rule 4, release→Rule 5; added general HEREDOC-body stripping before pattern-matching so authoring a file whose CONTENT mentions a gated command isn't blocked (fixes the reported false-positive AND the same latent class for rules 4/5).
- test-restrict-agent-spawn.sh: the prior file was ALREADY RED (7/41 fail) — an unadapted upstream fixture (partner/intern/test-intern, asserting gating the hook never had). Rewrote it against the real statbus roster (foreman/engineer/mechanic/operator/tester); dropped rule-4 identity cases; added heredoc regression cases + over-strip controls. Now 40/40 green.
- .claude/team/README.md + tester.md: updated to state test serialization is the flock, tester-single-runner is a coordination convention.

VERIFICATION (actual output):
- Lock helper exercised in isolation (real bytes extracted from dev.sh): (1) single run acquires+auto-releases; (2) concurrent → 2nd fails loudly exit 1 naming holder pid/started-at/action; (3) SIGKILL'd holder → next run reclaims stale lock, exit 0, no wedge; (4) re-entrancy: child with STATBUS_TEST_LOCK_HELD passes through and does NOT release parent's lock.
- Hook suite: 40/40 green. shellcheck -S warning: hook clean, no new warnings in dev.sh lock region.
All three acceptance criteria met.

REVISION (architect FIX-THEN-SHIP verdict, 2026-07-06): swapped the acquire CORE from mkdir+pidfile+kill-0 to a REAL kernel flock(2) driven by perl on an fd inherited from bash (`exec 9>>lockfile` in bash; `perl -e 'open(my $fh, ">&=", 9)...flock(LOCK_EX|LOCK_NB)'`). flock(1) is absent on macOS but perl is always shipped. This eliminates the mkdir stale-reclaim TOCTOU the architect found (contender A reads dead pid, B reclaims+relocks in the window, A's rm deletes B's live lock), the kill-0-on-dead-parent-while-children-still-mutating hazard, and PID-reuse false-blocks. The lock lives with the open file description: released by the kernel on whole-process-tree death (even SIGKILL), and HELD while any child of a killed run still has fd 9 open. Deleted the pidfile-liveness/spin/reclaim machinery (~40 lines); the holder file is now purely informational for the banner. STATBUS_TEST_LOCK_HELD re-entrancy + trap-chaining into cleanup_shared_test_db/cleanup_test_db kept verbatim. Added a self-heal for the one-time mkdir-dir→file transition.

BUG CAUGHT + FIXED during re-verify (empirical): `exec 9>&- 2>/dev/null` on a no-command exec PERMANENTLY redirects the shell's stderr to /dev/null — it was silently swallowing the loud contention banner (exit code was 1, but the banner was invisible). Fixed to bare `exec 9>&-` at both sites (fd 9 is guaranteed open when they run). Only caught because I checked the actual banner output, not just the exit code.

Adds: hook test (h) gated command AFTER a heredoc terminator → still DENY (resumption); (i) here-string on line 1 + real git push on line 2 → DENY (the `(^|[^<])` guard stops `<<<` being misread as a heredoc opener and swallowing the following real command). Commented the two known strip residuals (here-strings; interpreter-fed heredocs = deliberate-laundering, out of scope).

RE-VERIFIED (actual output, real dev.sh bytes extracted): ARM1 acquire+auto-release; ARM2 contention → exit 1 + LOUD banner naming pid/started-at/action; ARM3 whole-tree SIGKILL → released; ARM4 child outlives SIGKILL'd parent → lock still HELD, then child death → released; re-entrancy pass-through. bash -n + shellcheck clean; hook suite 42/42. Acquire diff saved at tmp/engineer-133-devsh.diff. Still NOT committed.
<!-- SECTION:NOTES:END -->

## Comments

<!-- COMMENTS:BEGIN -->
author: foreman
created: 2026-07-06 14:24
---
RE-SCOPED per the King (2026-07-06): identity-proof mechanism rejected as overengineering; serialization via flock in the test runner is the ruling. Foreman analysis concurs: the rule's stated WHY was concurrent-run corruption — a concurrency problem; identity was a proxy for serialization, and the direct primitive (flock, self-releasing on death) is strictly simpler and crash-proof. Old description's fix candidates (identity file / first-occurrence match / bounded grace) are all superseded.
---
<!-- COMMENTS:END -->
