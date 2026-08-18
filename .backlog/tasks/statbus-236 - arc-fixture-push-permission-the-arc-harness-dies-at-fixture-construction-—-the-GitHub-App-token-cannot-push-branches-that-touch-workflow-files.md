---
id: STATBUS-236
title: >-
  arc-fixture-push-permission: the arc harness dies at fixture construction —
  the GitHub App token cannot push branches that touch workflow files
status: In Progress
assignee:
  - '@engineer'
created_date: '2026-08-18 15:48'
updated_date: '2026-08-18 15:56'
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

author: engineer
created: 2026-08-18 15:52
---
**TRACE (read-only; no files modified). One premise in the filing does not survive: the fixture branches contain NO workflow-file edits. Neither the token nor the push path changed — MASTER MOVED.**

**Q1a — WHICH CREDENTIAL.** The default `GITHUB_TOKEN`, persisted by `actions/checkout@v4` (the construct job's checkout: "Default token is persisted by checkout so the pushes below authenticate"). Its scope is the workflow-level block at upgrade-arc-harness.yaml:107-110 — `contents: write`, `actions: write`, `packages: read`. **No `workflows:` entry.** GITHUB_TOKEN *is* a GitHub App token (github-actions[bot]), so the error's "a GitHub App" is this token, not a separate custom App.

**Q1b — WHAT CHANGED: the BASE, not the credential.** Verified by history: the `permissions:` block last changed **77fa16fb2, 2026-07-14** (the rebaseline root), and the push path (`test/install-recovery/lib/upgrade-target.sh`) last changed **2026-07-15**. Both untouched since. What changed TODAY: rc.04 was cut at **14:10**; master then advanced in `.github/workflows/` at **17:02** (a880ad26f — orchestrator + upgrade-arc-harness) and **17:04** (e03dee48f — install-recovery-harness.yaml, the file the error names). Fixtures are built off `base_sha` = the RC commit, so their tree carries rc.04's workflow files, which now differ from master's. That divergence is hours old.

**Q2 — DO B/C NEED WORKFLOW EDITS? NO — THEY MAKE NONE.** `construct_upgrade_target` stages exactly `git add migrations/` plus, for the codeonly spec, one non-workflow marker (upgrade-target.sh:471-477; commits at :482/:499/:506/:535/:545). **No fixture commit touches `.github/workflows/`.** Those files are INHERITED from the base commit, not authored by the fixture — so "fixture content includes workflow-file changes" is not the mechanism.

**THE MECHANISM, BY ELIMINATION** (GitHub's exact comparison basis is not verifiable from my sandbox — flagged as the one open premise):
- *"every file in a NEW branch counts as created"* → would have failed EVERY arc run ever → refuted by the historically green runs.
- *"the pushed COMMITS' diffs touch workflow paths"* → they demonstrably do not → predicts no failure → refuted by today's failure.
- *"the branch's TREE differs from the default branch under `.github/workflows/`"* → predicts failure exactly when master has advanced in workflow files since the base was cut → **matches both the historical successes and today's failure.** One candidate survives. The error naming a single file while three differed is consistent with GitHub reporting one representative path.

**FALSIFIABLE PREDICTION, worth knowing before choosing:** this failure is TIME-DEPENDENT, not code-dependent. Re-running at the same rc.04 base keeps failing while master differs; cutting the next RC from CURRENT master makes base == master and the push succeeds again. That is why it looks like an infrastructure fault and is not one.

**Q3 — REMEDIES.**

**(C) "keep workflow files out of the fixtures" is SELF-DEFEATING** — rule it out first. The fixture does not add those files; removing or rewriting them in the branch would ITSELF be a workflow-file modification, blocked by the same restriction. No fixture-side content change reaches a legal state.

**(B) a differently-scoped credential (PAT / custom App)** — works, but adds a long-lived secret with repo-wide push rights to avoid one declared permission. Worse foundation than (A).

**(A) RECOMMENDED — declare `workflows: write` on this workflow's own token**, in the existing `permissions:` block. Two corrections to the ticket's framing:
1. **This is a CODE change, not necessarily an org/App settings change.** `GITHUB_TOKEN`'s permissions are declared per-workflow; the org/repo setting only sets the CEILING. It becomes King-gated ONLY if that ceiling forbids it — which the run's error cannot tell us and I cannot check offline. **Try the one-line declaration first; escalate to the King only if the ceiling refuses it.** No org setting should be requested before that is known.
2. It remains a real widening, scoped honestly: that token could then modify CI definitions on any branch it pushes. Mitigations already present — the refs are throwaway `test/*` names, force-pushed and deleted by the `if: always()` teardown, and the token is job-scoped and short-lived. **There is no in-repo precedent** (no other workflow declares `workflows:`), so this would be the first — worth the architect's eye on that ground alone.

**A FOURTH OPTION, named so it is rejected on the record:** always cutting the RC from current master would dodge the divergence, but it makes arc correctness depend on master standing still during a suite — the same accidental-timing dependency this week's work has been removing.

**AC#4 — ZERO-SCOPE GUARD CONFIRMED INTACT:** construct failed, every scenario step skipped, and the suite went RED rather than green-with-zero-scope. The refusal machinery held; nothing there needs changing.
---

author: engineer
created: 2026-08-18 15:53
---
**SELF-CORRECTION on my own comment #4, before anyone acts on it. My (C)-refutation contradicts the mechanism I concluded three paragraphs earlier, and the architect's remedy direction is right where I was wrong.**

I eliminated *"the pushed COMMITS' diffs touch workflow paths"* as the mechanism — correctly, since the fixture commits touch only `migrations/` yet the push was refused. Then, ruling out remedy (C), I wrote that removing or rewriting the workflow files in the fixture "would ITSELF be a workflow-file modification, blocked by the same restriction". **That reasoning applies the commit-diff rule I had just refuted.** Under the rule that actually survived elimination — the branch's TREE versus the default branch — a fixture commit that makes those files MATCH master leaves nothing differing, so there is nothing for the restriction to refuse. The architect's shape is legal under my own conclusion; I argued against it using a rule I had discarded.

**Consequence: my recommendation (A) should NOT be treated as the trace's conclusion.** His objection stands on its own merits too — `workflows: write` hands a test harness's token the standing right to push arbitrary CI definitions, to avoid inert cargo on a throwaway branch. That is a privilege expansion bought to fix a symptom, and I ranked it first partly because I had wrongly closed off the cheaper door.

**His #1 also improves my Q1b answer, and I want the correction recorded.** I concluded "neither the token nor the push path changed — master moved". True as far as it goes, but he supplies the structural cause I was missing: **pre-214 the harness fired on the tag push itself, when the tag WAS master's tip — divergence was structurally impossible. Post-214 the orchestrator dispatches the fleet at a tag while master moves beneath it.** So something in the mechanism DID change (the trigger topology, via 214), even though the script and the permissions block did not. That also confirms his point that this recurs for ANY sufficiently old RC — my "cut the next RC from current master" observation is therefore a coincidence-dodge, not a remedy, exactly as I flagged but for a sharper reason than I gave.

**WHAT IS STILL GENUINELY OPEN, and it is the same premise both his remedy and my refutation hinge on:** GitHub's comparison basis — branch-tree-vs-default (his remedy works) versus any-commit-touching-workflow-paths (his remedy is refused, and the permission grant becomes unavoidable). My elimination argument favours the former on the evidence available, but it is an inference from three data points, not a measurement, and I cannot test it from this sandbox.

**CHEAPEST WAY TO SETTLE IT before any design is committed** — a one-shot probe in the 214/215 style, foreman-executed: from a scratch branch based on an OLD commit (one where `.github/workflows/` differs from master), push (a) the branch as-is → expect the same refusal, reproducing the failure outside the fleet; then (b) a second branch with one commit that copies master's `.github/workflows/` over it → if that push SUCCEEDS, the tree-comparison rule holds and the architect's remedy is proven legal before it is built; if it is REFUSED, the commit-diff rule holds, his shape is closed, and the decision genuinely narrows to the permission grant — at which point the King-gated framing in the original ticket becomes the right one after all.

I would rather spend one probe than have either of us design against an unmeasured platform rule — that is the same discipline doc-030 applied to the Stage-2 skipped-run question.
---

author: engineer
created: 2026-08-18 15:56
---
**BY-COMMIT ENUMERATION + PREMISE CHECK + REMEDY DESIGN. One premise needs a correction (ten files, not six), and the design has a shape that does NOT depend on the unmeasured platform rule.**

**THE SUSPECT SURFACE, WALKED BY COMMIT** (arc path since the last-green era, 2ab6126a1 → HEAD: upgrade-arc-harness.yaml, release-fleet-orchestrator.yaml, test/install-recovery/lib/, .github/actions/). Nine commits. The discriminating query answers itself in one line: **no commit since 08-02 touched `test/install-recovery/lib/upgrade-target.sh`** — the file that builds AND pushes the fixtures. So no commit made fixtures carry workflow content, and none moved the push onto a different token. The push path is byte-identical to the last green arc run.

**The commit that changed the topology is 816bd6ba4 (STATBUS-214, 08-18 13:55)** — its diff removes `push: tags: ['v*-rc.*']` from upgrade-arc-harness.yaml, exactly as the architect's #1 says. Before it, the harness ran AT the tag push, when tag == master tip, and divergence was structurally impossible. After it, the orchestrator dispatches the fleet at a tag while master moves on. **Archaeology closed: not the token, not the fixture content, not the pusher — the trigger topology, one commit, named.**

**PREMISE CHECK — one confirmed, one grown:**
- The permissions block is verbatim as stated: `contents: write`, `actions: write`, `packages: read`. No `workflows:`. ✓
- **The divergence is TEN files now, not six** — app_build_and_lint, fast-tests, go-test, images, install-recovery-harness, release-fleet-orchestrator, release, test-hardening, test-install, upgrade-arc-harness. Four more landed after he counted (17:25–17:54). Direction unchanged; the number growing within one afternoon is itself the argument that this must be designed for the general case.

**DESIGN. Both shapes below produce the SAME TREE — the fixture's `.github/workflows/` taken from the default branch. They differ only in the fixture commit's PARENT, and that single choice decides whether the remedy depends on the unmeasured rule.**

**Shape A — ALIGN (simple).** Fixture commits stay parented on A (the tag); the commit additionally copies the default branch's `.github/workflows/` over the RC's. Branch tree then matches default → legal under the tree-comparison rule. **But its own diff touches workflow paths, so it is REFUSED under the commit-diff rule.** Depends on the open premise.

**Shape B — REPARENT (premise-independent, my recommendation).** The fixture commit's PARENT is the default branch's tip; its TREE is A's tree + the migration, with `.github/workflows/` from the default branch. Then: its diff versus its parent touches only product paths — **no workflow path at all** → legal under the commit-diff rule; and its tree matches the default branch under `.github/workflows/` → legal under the tree-comparison rule. **It satisfies BOTH candidate rules, so it is correct whichever one GitHub actually applies** — which means it can be built before the probe rather than after it.

**Shape B's cost, named rather than discovered later:** the fixture branch no longer descends from A, so `git describe --tags` on it resolves through the default branch's ancestry. That string feeds VERSION at `./sb config generate` on the box. I found NO ancestry assertion anywhere in the harness (no merge-base/is-ancestor in lib/ or arcs/), and the box resolves the target by SHA and checks out a tree — it does not require B to descend from A. But the describe-string change is real and must be verified on one arc before the fleet rides it.

**A HAZARD BOTH SHAPES SHARE, and it is the strongest argument for keeping the change minimal:** the fixture tree becomes a HYBRID — the default branch's CI definitions running against the RC's scripts. `gh workflow run images.yaml --ref <fixture-branch>` executes the workflow file FROM THAT REF, so after this change the fixture image build runs master's images.yaml, not the RC's. Concretely today: master's images.yaml reads `ops/release/ci-exempt-paths.txt` and hard-fails if it is missing (:133-138). I checked — **rc.04's tree does contain that file**, so this RC is fine, and the failure mode is "fail toward full build", which is loud and safe. But an older RC could lack a file master's CI expects, and that is the general-case risk this remedy family carries.

**WHAT I WOULD NOT DO:** the permission grant, for the architect's reason and one of my own — it would leave the hybrid problem unsolved while buying a standing privilege; the fixture branch would still carry stale CI definitions, just pushable ones.

**PROBE STATUS:** still worth running, but Shape B DEMOTES it from a blocker to a confirmation — it would tell us whether the simpler Shape A was available, not whether the fix is legal.
---

author: architect (pinned by foreman)
created: 2026-08-18 15:56
---
PROBE BLESSED (architect) with three sharpenings, all about not mis-reading the result. (1) TRUTH TABLE IN THE PROBE FILE, both outcomes named on BOTH arms — arm (a) pushes a new ref at an EXISTING commit (zero new commits), so under the commit-diff rule it plausibly SUCCEEDS, and that success is the (C)-answer arriving early, not a failed probe: (a) refused ⇒ tree rule; (a) allowed ⇒ commit rule; (b) allowed ⇒ tree rule confirmed, remedy legal; (b) refused ⇒ commit rule, permission question returns King-gated. (2) Arm (b) must make the workflow tree match master EXACTLY, DELETIONS INCLUDED — copying over the top leaves files master has deleted, trees still differ, and a refusal would only prove the sync was partial. Same set, same contents. (3) RECORD WHICH FILE the refusal names — the real failure named install-recovery-harness.yaml; a refusal naming the same file ties the probe to THIS incident, the difference between reproducing the bug and reproducing a bug. ON THE RECORD: the tree-comparison mechanism is the architect's HYPOTHESIS fitting the evidence, not established fact — arm (b) decides whether his remedy is legal at all; if refused, he takes the permission question to the King himself with the reasoning. Probe workflow removed after the answer is read — no standing machinery.
---
<!-- COMMENTS:END -->
