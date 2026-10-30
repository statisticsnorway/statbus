---
id: STATBUS-222
title: >-
  recovery-zero-guard-twin: install-recovery has no loud refusal for a
  zero-scenario selection — the fleet's twin of the arc harness's guard
status: Done
assignee:
  - mechanic
created_date: '2026-08-18 09:50'
updated_date: '2026-08-18 15:04'
labels:
  - ci
  - install-recovery
  - quality-gate
dependencies: []
references:
  - .github/workflows/install-recovery-harness.yaml
  - .github/workflows/upgrade-arc-harness.yaml
priority: low
type: enhancement
ordinal: 222000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
WHAT THIS PART DOES: the install-recovery fleet discovers its scenario list and runs one VM job per scenario. Its sibling, the upgrade-arc harness, gained a guard in STATBUS-215: a run whose selection is empty (outside the one ratified green-skip case) fails red instead of concluding green with nothing executed.

WHAT GOES WRONG: install-recovery never got the twin. If its discover step ever produced count=0, run-scenario would silently skip and the run would conclude green — the "zero-selection succeeds" softness, on the OTHER fleet. Found 2026-08-18 by the mechanic while folding STATBUS-221 into the 214 pass; flagged, deliberately not fixed in that frozen unit.

THE DETAIL: install-recovery-harness.yaml has three jobs — discover, run-scenario (now with the explicit 221-hardened if), cleanup (always()). There is no job that fires red on count==0. Mitigations already in place soften but do not close it: the 216 empty-domain fixes make an empty scenario FOLDER fail loudly in the Go gate, and the release gate's completeness check would refuse such a run as proof. But the run itself still shows green in the Actions list, misleading anyone reading runs rather than gates.

THE FIX: a no-scenarios-guard job mirroring the arc harness's no-arcs-guard — fires red when discover succeeded with count==0, exempting any legitimate green-skip path this fleet has (none today; if a RIDE-style optimizer is ever added here, the exemption mirrors it, independently re-derived per the 215-review doctrine).

WHY THAT HELPS: both fleets then share one behavior — an empty run is a loud failure, never a quiet green — so nobody has to remember which fleet can be trusted by its color alone.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 A run whose discover succeeds with count==0 concludes red with a named error
- [x] #2 Any legitimate zero-selection path is exempted explicitly and independently re-derived, never read from a discover output
- [x] #3 The guard job cannot poison downstream ifs (the 215 audit applied at birth)
<!-- AC:END -->

## Comments

<!-- COMMENTS:BEGIN -->
author: mechanic
created: 2026-08-18 15:01
---
Built, frozen for review (no commits) — SEPARATE unit/diff from 223+220+225 (different file, install-recovery-harness.yaml, not touched by that unit at all).

Added `no-scenarios-guard` right after `discover`, before `run-scenario`, mirroring upgrade-arc-harness.yaml's `no-arcs-guard` in its POST-STATBUS-223 form (unconditional, no RIDE exemption) since this file has no RIDE-style mechanism to exempt — written for the post-223 world exactly as instructed, not the older RIDE-exempted shape:
```
no-scenarios-guard:
  name: Refuse zero-scenario run
  needs: [discover]
  if: >-
    ${{ !cancelled() &&
        needs.discover.result == 'success' &&
        needs.discover.outputs.count == '0' }}
  runs-on: ubuntu-24.04
  timeout-minutes: 5
  steps:
    - run: |
        echo "::error title=Zero scenarios selected::..."
        exit 1
```

AC#1 (red on count==0): satisfied — fires `::error` + exit 1 whenever discover succeeds with count==0.

AC#2 (exemption independently re-derived, never trusted from discover output): no exemption exists today, by design — the comment explains why (no RIDE/path-sensitivity mechanism in this file, matching the arc harness's own post-223 reasoning) and states the doctrine explicitly for whoever adds one later: it must be independently re-derived, never read from a discover output, mirroring the STATBUS-215 review's doctrine.

AC#3 (cannot poison downstream ifs, 215 audit at birth): verified structurally, not retrofitted — this job has exactly one need (discover) and NOTHING needs it back. `run-scenario`'s own `if:` (STATBUS-221) already independently guards on `needs.discover.outputs.count != '0'`, so it doesn't need or reference the guard job at all. `cleanup` is `if: always()` with `needs: [discover, run-scenario]` — doesn't reference the guard either, matching the arc harness's `no-arcs-guard` which nothing downstream needs there too (grepped to confirm). A red no-scenarios-guard therefore only ever changes THIS workflow's own conclusion, never cascades a skip anywhere.

THREE-PATH TRACE:
1. Full orchestrator dispatch (blank scenarios): discover succeeds, count~28 → guard's count=='0' false → SKIPPED. run-scenario runs the full matrix, cleanup sweeps. Normal green.
2. Manual dispatch, valid non-empty subset: discover succeeds, count=N>0 → guard skipped, run-scenario runs the subset. Normal green.
3. Manual dispatch, a selector that's syntactically valid but resolves to nothing (e.g. only HARNESS_SKIP_DEFAULT-excluded scenario names) — the case AC#1 exists for: discover's `--print-selected` succeeds (the name IS a real scenario, no bad-selector error) but the exclusion logic filters it out → count==0, discover.result=='success' → guard's if evaluates true → guard RUNS, fails red, names the error. run-scenario's own independent count!=0 check skips it (matrix never expands). cleanup still runs (always()). Overall workflow conclusion: FAILURE — AC#1 satisfied. (Distinguished from a genuinely BAD selector, which already fails discover itself — non-zero exit — before any count is ever produced; the guard correctly does not fire redundantly in that case since discover.result != 'success'.)

Validated: `ruby -ryaml` clean, `actionlint` exits 0 on this file (zero findings), confirmed against a full-repo actionlint sweep showing zero attributions to it.
---

author: architect
created: 2026-08-18 15:03
---
REVIEW VERDICT — APPROVED, no amendment. Clean unit; the structural claim is literally true rather than merely argued, and the comment does something better than the code.

AC#3 VERIFIED LITERALLY, not accepted: `no-scenarios-guard` appears exactly TWICE in the file — once inside its own comment, once as the job definition. NOTHING needs it back. So a red guard cannot cascade an implicit skip anywhere; it only flips the run's own conclusion, which is precisely what it is for. run-scenario's count check (221) and cleanup's always() are independent, as claimed.

CONDITION matches the arc harness's post-223 unconditional form exactly — `!cancelled() && discover.result == 'success' && count == '0'` — with discover-success required, so a failed discover reddens on its own rather than through this guard.

THE COMMENT IS THE BEST PART, and I want it protected. It carries the doctrine forward to whoever adds a green-skip path here later: an exemption must be INDEPENDENTLY RE-DERIVED, never read from a discover output, because the short-circuit that produced count==0 is not trusted to also vouch for its own legitimacy. That is my STATBUS-215 review ruling written at the exact point where the next person would otherwise violate it — prose placed where the hand will be, which is the only form of doctrine that survives. And framing the poison check as "applied at birth, not retrofitted" is the 215 audit discipline generalising proactively instead of after an incident.

ONE ADJACENT QUESTION I CHECKED SO NOBODY OPENS IT LATER: whether STATBUS-216's OTHER workflow-side twin — the unguarded shell glob that could enumerate the literal `*` as a scenario — also applies to this file. IT DOES NOT. This discover delegates selection to `run.sh --print-selected` as the single source of truth rather than globbing in YAML, and that script already fails loudly instead of producing an empty matrix. So there is no nullglob twin to add here, and the delegation is the better design regardless. Recorded so a future tidier does not helpfully port a fix into a file that has no need of it.
---

author: foreman
created: 2026-08-18 15:04
---
LANDED at e03dee48f, architect-approved with no amendment. His verdict highlights on the record: AC#3 verified literally (the guard appears twice in the file — its comment and its definition — and nothing needs it back, so a red can only flip the run's own conclusion); the doctrine-carrying comment called the best part of the unit and explicitly protected; and the adjacent 216-glob question checked and closed — this discover delegates selection to run.sh --print-selected (single source, already loud on empty), so there is no nullglob twin to port. Both fleets now share one rule: an empty run is a loud failure. Done.
---
<!-- COMMENTS:END -->
