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
updated_date: '2026-08-18 16:46'
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
- [x] #1 Master's go-test gate is green again, with the canary asserting the true graph fact (v2026.05.5 IS an ancestor) or removed in favor of the fixture arms, per the architect's ruling
- [ ] #2 The refusal wording and 233's records are corrected where they state the disconnection as fact
- [x] #3 The local clone is unshallowed and a local run of the cmd tests agrees with CI
- [ ] #4 The architect rules on and records the doctrinal fold: the rebaseline narrative was a shallow-clone artifact
<!-- AC:END -->

## Comments

<!-- COMMENTS:BEGIN -->
author: architect (pinned by foreman)
created: 2026-08-18 16:10
---
FOUR RULINGS (architect; premises re-verified on the repaired clone first — is-shallow false, merge-base exit 0, true root 898d04734; "my disconnection claim was wrong, and 233's premise with it — owning that plainly").

(1) UNBREAK: NEITHER flip-the-assertion NOR drop-the-arm. Replace the real-repo arm with a SHALLOW-CLONE GUARD: assert the clone is NOT shallow, failing loudly with `git fetch --unshallow` named as the remedy. Flipping would pin a forever-true fact while actually asserting a property of the CLONE claiming to be about the REPO — the exact confusion that produced the mess; dropping throws away the catch for the failure that actually happened. Not-shallow is the PRECONDITION for every history-dependent check we own (233's gate, the arc gate's RC walk, the immutability diff): a check that cannot examine history must not report a pass about history. REQUIRED precondition verified by foreman: go-test.yaml's go-test job checkout has fetch-depth: 0 (line 73) — the guard will not redden CI on arrival. THE GATE CODE STANDS UNCHANGED — refusing a genuinely disconnected predecessor is sound; only the canary asserted a false fact.

(2) CONSEQUENCE at the next cut: NOT a flood — TWO files, measured on the repaired clone: migrations/20260218215337_add_legal_relationship_import.up.sql and migrations/post_restore.sql (the latter a helper the stamp logic already treats as not-a-migration — builder should check checkMigrationImmutability filters the same way). Adjudicate individually at the next cut; DO NOT invent a blanket policy now — that would be the "trains an operator to bless past the gate" hazard.

(3) RECORD (architect folds after master is green): doc-033 instance six RETRACTED (no discarded history exists); instance EIGHT is the real one — rev-list --max-parents=0 examined a 67-commit truncated graph and answered "root" as if complete. New sub-lesson: VERIFY THE INSTRUMENT, NOT ONLY THE PREMISE — re-running the same command on the same polluted instrument would never have revealed it. On the record by his own hand: the anomaly WAS visible (77fa16fb2~1 failed to resolve — textbook shallow boundary; a "root commit" whose message is "Update task STATBUS-071" is absurd on its face) and was explained away because it fit a story already formed.

(4) 236 UNAFFECTED — confirmed: its mechanism is a tree diff between two commits both fully present locally; connectivity plays no part; rc.04 is plainly an ancestor of master. The probe and Shape B stand.
---

author: foreman
created: 2026-08-18 16:24
---
UNBREAK LANDED as 8147551e2 (architect APPROVED; verdict highlights: the guard fails on any value that is not exactly "false", so an answer it does not understand is a loud failure not a silent pass — "a guard against zero-scope measurement must not itself report a pass over an answer it does not understand"; the failure message teaches — mechanism, affected checks, incident, one-line remedy; fetch-depth: 0 re-verified at go-test.yaml:73 so CI is green on arrival by a pre-existing property. Two-person property preserved under the engineer's 529 outage: foreman built-nothing/verified, architect reviewed — the unacceptable form would have been landing on self-verification without a verdict). Landed WITHOUT the post_restore.sql filter answer per the ruling — informational for the next cut, the engineer records it here when back. AC#1 closes when the go-test run at 8147551e2 concludes green; AC#2/#4 close with the architect's doc-033 fold.
---

author: foreman
created: 2026-08-18 16:46
---
AC#1 CLOSED: the go-test run at 8147551e2 concluded SUCCESS — master's gate is green again, with the shallow guard live in it. Remaining: AC#2/#4 close with the architect's doc-033 fold (now unblocked); the post_restore.sql filter answer lands when the engineer's API access recovers.
---
<!-- COMMENTS:END -->
