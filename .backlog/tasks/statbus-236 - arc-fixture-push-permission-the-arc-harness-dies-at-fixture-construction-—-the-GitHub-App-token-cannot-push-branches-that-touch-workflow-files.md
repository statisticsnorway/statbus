---
id: STATBUS-236
title: >-
  arc-fixture-push-permission: the arc harness dies at fixture construction —
  the GitHub App token cannot push branches that touch workflow files
status: In Progress
assignee:
  - '@engineer'
created_date: '2026-08-18 15:48'
labels:
  - ci
  - install-recovery
  - release
dependencies: []
references:
  - tmp/agents/operator.md
priority: high
type: bug
ordinal: 236000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
The rc.04 suite verdict is RED because the Upgrade Arc Harness never ran a single scenario: fixture construction failed before matrix expansion, so all upgrade arcs are untested at rc.04. Until this is fixed and a green arc fleet observed, v2026.08.0 cannot be promoted.

WHAT THE EVIDENCE SHOWS (operator triage, 2026-08-18, run logs): orchestrator run 32149260642 dispatched all three fleets; fleets 1 (Test Install) and 2 (Install Recovery Harness) were green. Fleet 3's dispatch SUCCEEDED — downstream run 32156302719 exists — and that run failed at "Construct branch fixtures + dispatch image builds" with:

`refusing to allow a GitHub App to create or update workflow .github/workflows/install-recovery-harness.yaml without 'workflows' permission`

The step pushes test branch fixtures (B/C) whose content includes workflow-file changes, using a GitHub App token that lacks the `workflows` permission. Scenario steps all skipped; "Refuse zero-arc run" skipped too. The suite correctly went RED rather than green-with-zero-scope — the refusal machinery held.

OPEN QUESTIONS FOR THE TRACE (engineer): (1) which token does the fixture push use, and did this path ever work — prior arc runs (e.g. the 30755799405 era) built fixtures successfully, so what changed: the token, the fixture content newly touching workflow files, or the push mechanism? (2) Do fixture branches B/C NEED to carry workflow-file edits, or is that incidental content that could be excluded? (3) The candidate remedies differ in kind: granting the App `workflows` permission is an org/App settings change only the King can make; switching the push to a differently-scoped credential is config; keeping workflow files out of fixture branches is code. Determine which is the right foundation — not the quickest patch — and put the recommendation on this ticket for the architect's adversarial verify before anything is changed.

WHAT IS ACHIEVED WHEN DONE: the arc fleet can construct its fixtures again, the rc.04 (or successor) arc suite actually exercises the upgrade scenarios, and the promotion decision rests on a real verdict instead of a blocked one.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 The trace answers: which credential pushes fixtures, why it lacked workflows permission, and whether this path ever worked before (named prior run or commit)
- [ ] #2 A remedy recommendation is pinned on the ticket and adversarially verified by the architect before implementation; King-gated actions (App permission grants) are named as such, never self-authorized
- [ ] #3 The fix lands and a re-run of the arc fleet constructs fixtures and executes a non-zero number of scenarios
- [ ] #4 The zero-scope guard is confirmed intact: a fixture-construction failure still fails the run loudly
<!-- AC:END -->
