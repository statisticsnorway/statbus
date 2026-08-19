---
id: STATBUS-249
title: >-
  evidence-marks: a skip must name what it inherited, and cannot inherit from
  something never proven
status: To Do
assignee: []
created_date: '2026-08-19 09:06'
labels:
  - release
  - ci
  - quality-gate
dependencies: []
references:
  - .github/workflows/release-fleet-orchestrator.yaml
  - cli/cmd/release.go
  - ops/release/upgrade-sensitive-paths.txt
priority: high
type: enhancement
ordinal: 242000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Our expensive test suites may be skipped when a candidate changed nothing they cover — the candidate inherits the previous one's proof instead of re-renting 31 machines to learn the same thing. That is a sound saving, and it is currently built on an assumption nobody checks: **that the previous candidate was actually proven.** When it was not, the chain inherits from nothing and reports success.

THE SPECIMEN, and it is not hypothetical. rc.06's fleets were cancelled mid-chain, so its arcs never ran. rc.07 was then cut, compared itself against rc.06, found no upgrade-sensitive change, skipped the arc fleet — and its chain concluded **success** (Release Fleet Orchestrator run 32226442525 at commit ed0052d5e). Nothing had been proven about upgrade arcs at either candidate. The word "success" was reporting the absence of a reason to run, not the presence of a result.

WHAT IS ACTUALLY WRONG: the skip is keyed on **the previous TAG** rather than on **evidence**. `PREV_RC` is derived as "the RC tag before this one" and the diff is taken against it (release-fleet-orchestrator.yaml, the `decide-upgrade-sensitivity` job). A tag is a name, and a name says nothing about whether anything ran. The comment above that logic describes the intent exactly right — "inherit the previous release's proof instead" — and the code cannot tell whether a proof exists.

**A NECESSARY CORRECTION TO THE SEVERITY, verified rather than assumed: this could not have caused a bad promotion.** The stable release gate re-derives everything independently and refuses to ride a prior candidate unless that candidate's run is green AND every required arc job actually ran and succeeded, walking further back when it is not (cli/cmd/release.go, `checkUpgradeArcHarnessGate` and the path-sensitivity walk at 2072-2092). An unproven predecessor fails that test and is skipped as an anchor. So the file's claim that a wrong answer here "only costs an avoidable/skipped fleet dispatch, never a bad promotion" is TRUE, and it should not be reported as a near miss.

What it damages instead is the signal people act on. A chain that says success is read as "the tests passed", and here it meant "no test was owed against a predecessor that was itself never tested". The promotion gate would eventually refuse, but only later, after everyone had already believed the chain. **A green that means nothing is a defect even when a second gate catches it** — it teaches people the wrong thing about what green means, and it is the same shape as every other zero-scope green we have found: a check reporting on an examination it never performed.

THE FIX — MARKS, NOT NAMES. Each scenario that completes leaves a **durable, discoverable mark**: this scenario, at this code-state, passed. A later candidate asking "must I run this?" looks for the mark rather than reasoning about tags. Then:

- **Inheriting from something never proven becomes inexpressible.** You cannot find a mark that was never written. The false assumption is not detected and reported — it stops being representable, which is why this is a structural fix rather than an added check.
- **Granularity becomes per-scenario.** Today the decision is all-or-nothing for a whole fleet. Marks are per scenario, so a candidate can inherit the twenty-eight scenarios it did not touch and run the three it did.
- **Any verdict that inherited must SAY SO, naming the source** — "success — arcs inherited from &lt;commit&gt;" — never a bare success. A verdict that does not distinguish "ran and passed" from "did not need to run" is not reporting its own scope, which is the defect that produced the specimen above.

This is the per-scenario stamp design already ratified for the install-recovery harness, generalized to the whole chain. Worth noting that the principle is not new to this codebase and is not being invented here: the Go release gate ALREADY requires a complete, actually-succeeded anchor before it will let anything ride a prior green. This entry propagates a discipline we already have, from the layer that got it right to the layer that got it wrong.

WHY THAT HELPS: the saving is kept and the lie is removed. A chain's verdict comes to mean exactly what it says — either this was proven here, or it was proven there and here is where — and no candidate can ever again inherit a proof that does not exist.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Each completing scenario writes a durable, discoverable mark identifying the scenario and the code-state it passed at
- [ ] #2 The skip decision is made by looking for a mark, never by comparing tag names or assuming a predecessor was proven
- [ ] #3 Inheriting from an unproven predecessor is structurally impossible — no mark exists to be found — rather than being detected and reported
- [ ] #4 Inheritance is per-scenario: a candidate can inherit the scenarios it did not touch while running the ones it did
- [ ] #5 Any verdict that inherited or skipped names what it inherited from; a bare 'success' covering un-run work is a failure of this entry
- [ ] #6 A superseded or cancelled chain writes no marks for work that did not complete, so nothing downstream can ride it (STATBUS-246)
- [ ] #7 The rc.07 specimen is replayed against the new mechanism and produces a verdict that names its scope instead of a bare success
- [ ] #8 Marks are composable from a local run or from CI, per the ratified install-recovery stamp design
<!-- AC:END -->
