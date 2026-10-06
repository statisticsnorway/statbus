---
id: STATBUS-454
title: Fast Tests hides regression diffs after the split result layout
status: In Progress
assignee: []
created_date: '2026-10-06 15:03'
labels:
  - ci
  - testing
dependencies: []
references:
  - STATBUS-452
priority: high
---

## Observed failure

Exact 49bb Fast Tests run 37481764536 failed on 008 and 016, 100/102 tests passed. Its failure diagnostic step ran `cat /statbus/test/regression.diffs 2>/dev/null || true` and printed no diff. The existing helper uses test/regression.out and the expected/results files instead of that assumed diff path. There were no uploaded artifacts to recover. Root retained actual logs in tmp/452-fast-failure-49bb-20261006.log and tmp/452-fast-diffs-49bb-20261006.log. The shared/isolated runner source was inspected, but no live output aggregation producer was reproduced. This required isolated SQL reproduction to obtain the exact diffs.

## Small fix

Use the existing read-only `./dev.sh diff-fail-all pipe` helper in the failure step. It reads the actual combined regression inventory and compares the failed tests' committed expected/result files. Do not invent another result-layout adapter, suppress the original test failure or add a workflow architecture.

## Acceptance Criteria

- [x] #1 Observe the old file-reading payload producing no diff from an offline fixture with failure inventory/result files. The Docker wrapper and live producer are not claimed reproduced.
- [x] #2 Corrected diagnostic invokes the actual unchanged helper and prints both representative failing test diffs. No database access or mutation in this fixture.
- [ ] #3 Changed workflow passes actionlint; independent exact-source review and patch/source proof before integration.
- [ ] #4 Next exact-source CI retains its true test conclusion. A future failing run's diff step is useful without making the test pass or replacing actual schema-contract repair.

## Safety

Only fast-tests.yaml's failure diagnostic command and a small existing-pattern offline fixture check may change. No production, database, cloud, credentials, external callback or CI mutation. Separate isolated source worktree, no master/index writes or push. Use captured original failure as baseline evidence and report local fixture limits honestly.

## Implementation checkpoint, 2026-10-06 15:09 UTC

Otter froze one workflow-only commit 5b277d6d4c918e71913c3a3674590c62af091c7d from b8a9d0e33, +1/-2. It replaces the obsolete command with ./dev.sh diff-fail-all pipe and preserves if: failure(), with no new outer error suppression or continue-on-error. Root read the exact delta and own tmp/journal.md, 454-offline-check.sh and 454-prototype.log. Baseline cat payload prints zero bytes. The actual unchanged full dev.sh prints both named expected/changed diffs, exit 0. The fixture prepares an independent git repo, inert seed-cache placeholder and a startup-only sb double rejecting all non-drift invocations. No real DB, Docker, configuration, credentials or live CI result producer is exercised. Actual full actionlint, syntax and diff checks pass. Panda is authorized to independently review this exact pin before integration. Original hosted test conclusion remains failure, corrected hosted acceptance still pending.
