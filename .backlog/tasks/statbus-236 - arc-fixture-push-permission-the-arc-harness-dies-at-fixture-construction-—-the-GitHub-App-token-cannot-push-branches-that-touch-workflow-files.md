---
id: STATBUS-236
title: >-
  arc-fixture-push-permission: the arc harness dies at fixture construction —
  the GitHub App token cannot push branches that touch workflow files
status: In Progress
assignee:
  - '@engineer'
created_date: '2026-08-18 15:48'
updated_date: '2026-08-18 15:50'
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

## Comments

<!-- COMMENTS:BEGIN -->
author: architect (pinned by foreman)
created: 2026-08-18 15:50
---
MECHANISM FOUND (architect, verified on the tree): six workflow files differ between the rc.04 tag (1187d2950) and current master (5e4dcad69), including install-recovery-harness.yaml — the exact file the refusal names. The chain: (1) the arc harness runs at the TAG, whose tree is behind master; (2) construct cuts fixture branches from base_sha = the tag commit and pushes them; (3) GitHub compares a new branch's workflow files against the default branch — the fixture carries rc.04-era copies, master's have moved, so the push registers as "create or update workflow file"; (4) upgrade-arc-harness.yaml declares contents:write, actions:write, packages:read — no workflows:write — so the push is refused. WHY IT NEVER HAPPENED BEFORE: pre-214 the harness fired on the tag push itself, when the tag WAS master's tip — zero divergence, always legal. Post-214 the orchestrator dispatches the fleet at a tag while master moves beneath it. This recurs on ANY RC more than a few workflow-touching commits old — the remedy must handle the general case, not this tag.
---

author: architect (pinned by foreman)
created: 2026-08-18 15:50
---
REMEDY DIRECTION (architect, not a design — engineer designs, architect adversarially verifies): the permission grant is the WRONG answer and last resort — it hands a test harness's token the right to push arbitrary workflow files, a real privilege expansion, and treats the symptom. The fixture branches have no business differing in .github/workflows/ at all: they exist to give the image builder a tree with a migration added; workflow files on a throwaway test branch are inert cargo that happens to be privileged. The remedy space is "stop the fixture branch from differing in .github/workflows/". KNOWN TRAP: deleting those files in the fixture commit is ITSELF a workflow change and would be refused identically. Making the fixture's copies match the default branch's is legal and harmless (the arc tests migrations and upgrade, not workflows) — but there may be a cleaner shape.
---

author: architect (pinned by foreman)
created: 2026-08-18 15:50
---
SCOPE CORRECTION on the run's meaning (architect): the red is trustworthy but almost entirely UNINFORMATIVE — zero scenarios ran, so rc.04's suite has proven nothing yet about rollback, un-park, or anything landed today. The re-run after this fix is the one that carries the evidence.
---
<!-- COMMENTS:END -->
