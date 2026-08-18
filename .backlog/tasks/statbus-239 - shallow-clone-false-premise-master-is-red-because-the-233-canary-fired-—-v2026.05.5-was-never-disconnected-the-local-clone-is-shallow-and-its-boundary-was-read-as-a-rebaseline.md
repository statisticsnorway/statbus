---
id: STATBUS-239
title: >-
  shallow-clone-false-premise: master is red because the 233 canary fired —
  v2026.05.5 was never disconnected; the local clone is shallow and its boundary
  was read as a rebaseline
status: In Progress
assignee:
  - '@engineer'
created_date: '2026-08-18 16:08'
labels:
  - release
  - quality-gate
  - tooling
dependencies: []
references:
  - cli/cmd/immutability_disconnected_test.go
  - cli/cmd/release.go
priority: high
type: bug
ordinal: 239000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Master's go-test gate is red, and the failure is a canary doing its job: TestRealRepo_PreRebaselineTagIsDisconnected_STATBUS233 asserts v2026.05.5 is not an ancestor of HEAD, and in CI's full clone it provably IS. The disconnection that STATBUS-233 was premised on never existed — it was an artifact of our local clone being shallow.

THE EVIDENCE (foreman, 2026-08-18, verified against GitHub's authoritative graph):
- `.git/shallow` exists in the working clone — 67 boundary commits. The local graph is CUT, not complete.
- 77fa16fb2, the supposed "rebaseline root", HAS A PARENT (bab043771) — visible in the local commit object itself (`git cat-file -p`) and confirmed by GitHub's API. `git rev-list --max-parents=0 HEAD` reported it as a root only because rev-list treats shallow-boundary commits as parentless.
- GitHub compare f7a747e41 (v2026.05.5^{})...master: status "ahead", ahead_by 2154, behind_by 0 — the tag is a genuine ancestor of master. Local `merge-base --is-ancestor` exit 1 was the shallow boundary lying.
- Local and remote tags agree exactly (be566387 → f7a747e41), so tag drift is ruled out.

CONSEQUENCES TO SORT (architect rules the shape):
1. The real-repo canary test's assertion is factually wrong about this repository and must change — the test's own failure message anticipated this exact moment and says what to do: re-read the premise.
2. The gate CODE (refuse a genuinely disconnected predecessor rather than print noise) remains sound defensive engineering on its own merits — nothing in this finding says the ancestor check is wrong, only that this repo never needed it for v2026.05.5.
3. With v2026.05.5 connected, the immutability gate's previous-stable comparison is MEANINGFUL — the "noise flood" scenario does not exist here. Whether the real diff v2026.05.5..HEAD is quiet or shows genuine migration edits is now a real question the gate will answer at the next first-RC.
4. The "rebaseline of 2026-07-14" story embedded in tickets, docs, and working lore came from measuring a shallow clone. The record needs a correction (doc-033 family — an entire institutional narrative from one polluted instrument).
5. The local instrument is being repaired: git fetch --unshallow is running. Local test runs will then agree with CI.

WHAT IS ACHIEVED WHEN DONE: master's gate is green again on a test that asserts the TRUE graph; the false rebaseline narrative is corrected in the durable record; and the 233 refusal machinery survives for the case it actually guards — a predecessor that genuinely shares no history.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Master's go-test gate is green again, with the canary asserting the true graph fact (v2026.05.5 IS an ancestor) or removed in favor of the fixture arms, per the architect's ruling
- [ ] #2 The refusal wording and 233's records are corrected where they state the disconnection as fact
- [ ] #3 The local clone is unshallowed and a local run of the cmd tests agrees with CI
- [ ] #4 The architect rules on and records the doctrinal fold: the rebaseline narrative was a shallow-clone artifact
<!-- AC:END -->
