---
id: STATBUS-236
title: >-
  arc-fixture-push-permission: the arc harness dies at fixture construction —
  the GitHub App token cannot push branches that touch workflow files
status: In Progress
assignee:
  - '@engineer'
created_date: '2026-08-18 15:48'
updated_date: '2026-08-18 20:11'
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
- [x] #1 The trace answers: which credential pushes fixtures, why it lacked workflows permission, and whether this path ever worked before (named prior run or commit)
- [x] #2 A remedy recommendation is pinned on the ticket and adversarially verified by the architect before implementation; King-gated actions (App permission grants) are named as such, never self-authorized
- [ ] #3 The fix lands and a re-run of the arc fleet constructs fixtures and executes a non-zero number of scenarios
- [x] #4 The zero-scope guard is confirmed intact: a fixture-construction failure still fails the run loudly
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

author: architect (pinned by foreman)
created: 2026-08-18 15:58
---
VERDICT (architect): (1) SHAPE B APPROVED as the build direction — checked, not taken: under the tree rule any divergent branch is refused regardless of diff; under the commit-diff rule the aligning commit is itself refused; the only escape is a parent that ALREADY carries aligned workflows, which is exactly B. No Shape C exists. ONE REQUIRED CHECK before a fleet rides it: the reparent makes the fixture commit's diff-vs-parent a MASS REVERT of every product change between the RC and master (legal — no workflow paths — but visible to anything reasoning about "what this commit changed"). Enumerate the consumers of parent..commit on fixture branches; check the seed job's incremental logic (STATBUS-116) FIRST — it looks for new migrations and would now also see master's migrations vanishing. images.yaml's decide-exempt-only is fine by inspection: workflow_dispatch has no event.before, so it takes the fail-toward-full-build arm — by design, not luck. (2) PROBE RUNS IN PARALLEL, not as a gate, and not demoted to mere confirmation: if it returns the TREE rule, Shape A becomes available and is STRICTLY BETTER (parent stays the RC, diff is one migration + alignment, the mass-revert artefact and every consumer question disappear). Its value is "is there a simpler correct shape to switch to". Keep the arm-(a) file-name tie binding the reproduction to THIS incident. (3) HYBRID: accept as-is, ticket it, NO guard — failure mode is loud CI failure never a silent wrong verdict, and a guard would need to enumerate every file master's CI might read from an arbitrary older tree (unbounded, rots faster than what it guards). The ten-files-not-six measurement is the argument: this is what EVERY RC looks like within hours — premise-independence over elegance.
---

author: architect (pinned by foreman)
created: 2026-08-18 16:03
---
PROBE APPROVED + ARM (c) RULED IN (architect). Permissions-block fidelity verified — copying the harness block whole, unneeded scopes included, was right: fidelity to the fleet's authority IS the measurement. The engineer's third-rule reading CHECKED AND CONFIRMED: rule (D) (new commits diffed against the DEFAULT branch) is consistent with both (a)=allowed and the fleet refusal, where parent-diff (C) cannot explain the fleet refusal; Shape A is legal under (T) and (D), illegal only under (C), so arm (b) alone discriminates (C) from {(T),(D)} — exactly the remedy question. ARM (c) — direct Shape B test — IS A YES, because Shape B's premise-independence is an argument over an enumeration WE invented, and today's record is a list of incomplete enumerations (one door of two; five costumes then six then seven). Twelve lines in a dispatch already happening beats finding an un-enumerated rule on a fleet run (VMs, an hour, a second red suite). THREE CONDITIONS on (c): (1) construct it EXACTLY as the remedy will be — parent = origin/master tip, tree = rc.04's product + master's .github/workflows/ + the migration; no simplification (the fixture-simplification trap that made 219 inert), guarded by the same tree-level git diff --quiet check as arm (b), failing loudly as setup-failed; (2) capture the refusal file name, same as (a)/(b); (3) truth-table line, loud: "(c) refused ⇒ a rule we have not enumerated governs — STOP, the approved remedy is not legal, escalate." The arm turns an unknown-unknown into a named visible result instead of a fleet-run surprise.
---

author: architect (pinned by foreman)
created: 2026-08-18 16:03
---
DEFINITIVE TRUTH TABLE (architect) — supersedes every earlier statement of it; the reconcile transcribes from THIS comment only. Rule for the future: a probe's truth table is RE-DERIVED from the current ruling at freeze, never transcribed from an earlier statement (the stale (b)-refused line was comment #7's wording, falsified by verdict #8 — stale premise and documentary zero-scope in one line, and it would have sent a security-relevant permission request to the King on a false premise).

CANDIDATE RULES: (T) pushed ref's .github/workflows/ tree differs from default branch. (C) any new commit's diff AGAINST ITS PARENT touches .github/workflows/. (D) any new commit's tree AGAINST THE DEFAULT BRANCH differs under .github/workflows/.

PREDICTED OUTCOMES: arm (a) existing rc.04 commit, zero new commits — T:REFUSED C:ALLOWED D:ALLOWED. Arm (b) rc.04 + one aligning commit (= Shape A in miniature) — T:ALLOWED C:REFUSED D:ALLOWED. Arm (c) parent=master tip, tree=rc.04 product+master workflows+migration (= Shape B exactly) — T:ALLOWED C:ALLOWED D:ALLOWED.

READINGS: (a) REFUSED ⇒ rule (T); Shape A available and PREFERRED over B (simpler diff, no mass-revert, no consumer questions). (a) ALLOWED ⇒ (T) eliminated, (b) decides: (b) ALLOWED ⇒ (D), Shape A legal and preferred; (b) REFUSED ⇒ (C), Shape A dead, SHAPE B REMAINS LEGAL AND PROCEEDS, NO permission question (the formerly stale line). (c) REFUSED under any combination ⇒ a rule OUTSIDE this enumeration governs — STOP, the approved remedy is not legal, escalate — and this is the ONLY branch on which the permission question returns.
---

author: engineer
created: 2026-08-18 16:05
---
**SHAPE B BUILT + THE REQUIRED CONSUMER CHECK. FROZEN for review (no commit). One file: `test/install-recovery/lib/upgrade-target.sh`.** The dry run caught a real bug in my first implementation — details below, because it is the most important thing here.

**REQUIRED CONSUMER ENUMERATION — every consumer of `parent..commit` on a fixture branch, each ruled:**

1. **Seed incremental gate (STATBUS-116) — SAFE, for a better reason than expected.** `SeedBuildDecision` (cmd/seed.go:622-640) reads **no git diff at all**: it compares the prior seed's recorded fingerprint against one recomputed over the CURRENT ON-DISK migrations ≤ the prior version. A TREE-content check — and Shape B changes only the PARENT POINTER; the tree is byte-identical to today's outside `.github/workflows/`. The concern that it "would see master's migrations vanishing" does not arise: it never looks at a diff.
2. **Prior-seed SELECTION — AFFECTED, safe, costs build time.** `SelectPriorSeed` (cmd/seed_ancestor.go:53) DOES walk ancestry — `git rev-list --first-parent` (:73) — and images.yaml:433 runs it on the fixture branch. With the default branch as parent it now reaches **master-era** seeds instead of RC-era ones; the fixture tree deliberately lacks master's newer migrations, so the fingerprint typically MISMATCHES and the build falls back to a **FULL seed rebuild**. Never incorrect (the gate fails toward full, and a missing migration changes the fingerprint), but slower on all 11 fixture branches. **Recorded as an accepted cost, not fixed here:** avoiding it means a merge-commit shape (another unmeasured guess about GitHub's rule) or teaching images.yaml to start the walk at BASE_SHA (mechanic's file, more machinery). If the probe proves the tree rule, Shape A avoids it entirely — another reason to keep the switch cheap.
3. **images.yaml `decide-exempt-only` (`github.event.before`) — SAFE**, as ruled: dispatched via `workflow_dispatch`, which has no `event.before`; images.yaml:393 says so and takes the fail-toward-full-build arm.
4. **Release gates** (release.go:852/954/1664, release_verify.go:96) — the only other `A..B` consumers. They compare against TAGS, run on master at release time, never on a fixture branch. **Not consumers.**

Complete set; the grep behind it covered `HEAD~`/`HEAD^`/`event.before`/`git diff A..B`/`git log A..B` across `.github/`, `test/install-recovery/`, `cli/`.

**IMPLEMENTATION:** one helper (`_ut_fixture_base`) plus one changed line at the B-branch cut. It returns a commit whose PARENT is the default-branch tip and whose TREE is BASE_SHA's, with `.github/workflows/` from the default branch. Its header records why reparenting beats overwriting in place: it satisfies BOTH candidate GitHub rules, so it is correct whichever the probe proves.

**THE DRY RUN CAUGHT A BUG THAT WOULD HAVE SHIPPED A GREEN, MEANINGLESS FLEET.** My first version used `git rm -r . && git checkout <base> -- .`. The `rm` refuses on locally-modified files, **its failure was swallowed by a `>/dev/null`**, and the fixture tree came out as MASTER's tree with the base's files layered on top — it pushed fine, it would have gone green, and every arc would have tested an upgrade to master's product code instead of the RC's. `git read-tree -u --reset` is the correct primitive (it also REMOVES paths the base lacks). **I found it only because I verified the resulting tree instead of trusting `EXIT=0`.**

The helper now carries TWO self-checks, each catching what the other cannot: **(1) pushability** — nothing differs under `.github/workflows/`; **(2) correctness** — outside it, the tree equals the base's byte for byte. (2) is the one that matters: a wrong tree still pushes and still goes green.

**VERIFICATION — offline dry run in a throwaway clone (never the shared tree), against the real rc.04 commit:**
- `.github/workflows/` byte-identical to master ✓
- product tree vs rc.04 = ONLY the four fixture migration files ✓
- commits touching a workflow path, branch vs master: **0** ✓ (legal under the commit-diff rule too)
- first-parent chain: fixture commit → fixture base → **master tip** (58c33668 == 58c33668) ✓
- `bash -n` clean; shellcheck warnings unchanged at 7 (all pre-existing, none mine)
- **assertion (2) RED-verified:** reinstating the old primitive exits 1 with "the arc would upgrade the box to the wrong code".

**VERSION-STRING OBSERVATION, still owed post-land:** the fixture no longer descends from the RC, so `git describe --tags` resolves through the default branch's ancestry, and that string feeds VERSION at `./sb config generate` on the box. Nothing in the harness asserts ancestry (verified: no merge-base/is-ancestor in `lib/` or `arcs/`) and the box resolves its target by SHA, so I expect no behavioural change — but it is unverified until observed. **Verification path: the first post-land arc run's box log shows the VERSION/commit_version it generated; one arc suffices, and it must be read before a full fleet rides on it.**
---

author: architect (pinned by foreman)
created: 2026-08-18 17:21
---
PROBE APPROVED (architect, fresh review). Arm (c) meets all three conditions, and GUARD 2 exceeds the ask — a guard against the probe PASSING WHILE MEASURING THE WRONG SHAPE: "a tree carrying master's product code pushes and goes green while measuring a shape the remedy never produces" — a zero-scope green inside the instrument, same class as 239's shallow clone, caught before dispatch rather than after the narrative. Pathspec excludes right: workflows aligned deliberately, two migration files deliberate, everything else must equal the rc.04 base byte-for-byte or the arm refuses to run. Verified by the reviewer directly: --detach origin/master parent; read-tree -u --reset (survives the rm-swallowed-error class); workflows from origin/master; migration pair makes (c) the WHOLE remedy; markers + refusal file-name capture; confirmation line prints the parent SHA so the run's own log proves the shape measured. The STOP/escalate line is the ONLY permission branch in the file — the permission question has exactly one door and it is labelled. Also recorded: the collision class prevented itself same-day (mechanic read before writing, recognized finished work, held). LANDING AND DISPATCHING NOW; operator reads the markers. Next in review queue: Shape B (the parent..commit consumer check gets the hardest look), then the doc-033 fold.
---

author: operator (pinned by foreman)
created: 2026-08-18 17:23
---
PROBE RESULT (run 32165178946, operator reading, verbatim markers):
PROBE236_A=refused
PROBE236_A_FILE=.github/workflows/install-recovery-harness.yaml
PROBE236_B=pushed
PROBE236_B_FILE=none
PROBE236_C=pushed
PROBE236_C_FILE=none
Parent confirmation: PROBE_BASE_SHA 1187d29505a5398e159543039abb3b767e707245 (rc.04 tip).

TRUTH-TABLE READING (comment #10, mechanical): (a) REFUSED ⇒ RULE (T) — the pushed ref's .github/workflows/ tree differing from the default branch is what GitHub refuses, regardless of commit diffs. (b) pushed confirms: an aligned tree is legal even though the aligning commit itself touches workflow paths — (C) and (D) are eliminated. (c) pushed: Shape B is ALSO empirically legal — the approved remedy was proven by direct measurement, no un-enumerated rule surfaced, the STOP/escalate branch was not taken.

INCIDENT TIE: arm (a)'s refusal names install-recovery-harness.yaml — the identical file the fleet's fixture push refused on (run 32156302719). This is a reproduction of THE incident, not a similar one.

FOREMAN CORRECTION to the operator's gloss: "branch protection" is not the mechanism — the mechanism is the workflows-permission rule keyed on tree comparison (rule T exactly as enumerated). The table lookup itself is correct.

CONSEQUENCE PER VERDICT #8: rule (T) means SHAPE A becomes available and is PREFERRED — parent stays the RC commit, diff is one migration + workflow alignment, the mass-revert artefact and every parent..commit consumer question (including the full-seed-rebuild cost on all 11 branches) disappear. Architect rules on the switch.
---

author: architect (pinned by foreman)
created: 2026-08-18 17:24
---
RULING: SWITCH TO SHAPE A (architect). The trade is not one build-review cycle vs a proven-legal shape — it is one cycle vs a PERMANENT cost plus two standing verification obligations: shipping B keeps (i) a full seed rebuild across eleven fixture branches on every arc run forever (master-era prior seeds mismatch), (ii) the git-describe/VERSION change requiring live-arc verification before any fleet rides, (iii) the parent..commit consumer enumeration. Under Shape A all three DO NOT EXIST — the switch deletes work, it does not add it. Deeper: declining the answer would waste the measurement — the probe's stated value was "is there a simpler correct shape to switch to", and it answered yes; shipping B would choose the legal over the right, having just paid to learn the difference. Shape A's legality is EMPIRICAL: arm (b) IS Shape A and it pushed. (Honest note: (b) lacks the migration that (c) was required to carry — material before the rule was known, immaterial now: under rule (T) only the workflow tree is examined and a migration is a product path.)

REVIEW CHECKLIST for the revised diff: (1) both self-checks survive the parent change — workflows equal origin/master exactly, product tree equals base + exactly the fixture migration; Guard 2's PURPOSE survives even as its shape simplifies. (2) ONLY the parent changes — same read-tree -u --reset at the base, same workflow overlay, same failure-loud arms; construction drift = a third shape, not a switch. (3) --detach origin/master fully removed, not left unused — a half-applied switch is how a shape becomes a hybrid nobody intended. No new exposure vs B: the hybrid hazard (STATBUS-238) is unchanged in kind and severity. Probe file removal rides the remedy's landing series.
---

author: architect (pinned by foreman)
created: 2026-08-18 17:35
---
SHAPE A APPROVED (architect; all three checklist points verified at source). Highlights: read-tree kept and honestly relabelled as a checkout-verifying no-op — better judgement than removing it for tidiness, since the assertions follow the identical primitive Shape B was reviewed under. Residual Shape B mentions all correct to keep: A COMMENT DESCRIBING A REJECTED ALTERNATIVE IS NOT A STALE PREMISE; a comment describing current behaviour incorrectly is — he kept the right ones and fixed the wrong ones, the harder half of the rule. The wording fixes were REQUIRED, not scope creep — the nothing-to-commit fallback naming the default ref would have been factually FALSE about which commit the fixture base is under Shape A: a correctness fix in the message layer, on an operator-facing line. The fallback is not a bypass (checked): when the base's workflows already equal the default branch, the fixture base IS the base SHA — legal precisely because they match; both self-checks run on that path and pass trivially — the no-op route is validated by the same guards as the mutation route. Habit named: verifying the workflow-touching diff IS present (11 files) rather than asserting absence — measuring the thing that would have been assumed. LANDING THE SERIES with the probe removal; the fleet re-run is the first suite in this campaign that can actually tell us whether rollback, un-park and the rest hold.
---

author: foreman
created: 2026-08-18 17:36
---
LANDED: Shape A as 65fa3fd09; probe removed as b2c3e7c61 (answer pinned, no standing machinery). AC#1/#2/#4 closed; AC#3 awaits a re-run that constructs fixtures and executes scenarios.

RE-DISPATCH MECHANICS, verified in the workflow before dispatching anything: upgrade-arc-harness.yaml takes a workflow_dispatch `base_sha` input that wins over GITHUB_SHA (:195-205, "ad-hoc base_sha" is a designed path). This matters because a dispatch at --ref v2026.08.0-rc.04 would execute the TAG's tree — which lacks the fix. The fixed code only runs from master's tree. Two candidate shapes for the re-run, each with a different value:
(1) Dispatch on master with base_sha=1187d2950: executes the FIXED construct against rc.04's base — real scenario evidence for rc.04's upgrade fixes, hours from now — but the run's head_sha is master's tip, so the release gate at the rc.04 commit will NOT see it (gates key on runs AT the commit).
(2) Cut rc.05 from current master (King's act): the orchestrator runs the full chain at the new tag, gate-visible, and everything landed today rides it — but the arc evidence arrives only after the cut decision plus the full chain.
Architect shapes the recommendation; the release-cut half is the King's decision either way.
---

author: architect (pinned by foreman)
created: 2026-08-18 17:38
---
RE-RUN RECOMMENDATION (architect): OPTION 2 ALONE — cut the next candidate; the CUT IS THE EVIDENCE RUN. The fork's framing hid the decisive fact: a fresh tag's chain exercises exactly the repairs we most need to see (rollback, un-park) against a tree containing the fixture fix — one fleet, both outcomes (evidence AND gate-visibility). Option 1 buys the same knowledge a few hours earlier for the price of a second full fleet, and the earliness has NO DECISION attached: knowing at 8pm vs midnight changes nothing we would do — red means fix-and-cut-again from the same place, clean means promote, either way. Nothing is wasted on a red: a tag is free, and "we cut and it failed" is the measurement arriving, wearing a tag. rc.04 is SUPERSEDED, not rejected — its own tree carries the broken construct, so it can never produce its own arc proof at any price. The one flip-condition, answered: an evidence-first run would be right if the harness repair itself were unproven — it is not; the probe measured the governing rule directly and the repair was built to the measurement. What remains untested downstream of the push ran fine in earlier suites — ordinary risk, identical under either option. King's brief delivered by foreman; the cut is the King's act.
---

author: foreman
created: 2026-08-18 17:44
---
FILTER ANSWER (foreman, verified at source — taking the engineer's owed item off his stuck session): checkMigrationImmutability filters non-migration housekeeping exactly as the stamp logic does. release.go:888-891 — only files ending .up.sql/.down.sql/.up.psql/.down.psql carry the immutability constraint; everything else under migrations/ is skipped with the comment "directory placeholders (.gitkeep) and other housekeeping files ... aren't deployed migrations". post_restore.sql matches none of the four suffixes → skipped. CONSEQUENCE for the next cut (per 239 ruling 2): the previous-stable comparison v2026.05.5..HEAD will surface exactly ONE file for adjudication — migrations/20260218215337_add_legal_relationship_import.up.sql — not two; the gate itself already handles the other. The engineer's queue is now empty.
---

author: foreman
created: 2026-08-18 20:11
---
THE RE-RUN IS LIVE: v2026.08.0-rc.05 cut at b4fd437fe (King's act, 2026-08-18 ~19:55 UTC), orchestrator run 32180844587 in progress — the first chain whose arc fleet executes the FIXED fixture construction (Shape A, 65fa3fd09) from its own tag's tree (tag == recent master, divergence near zero AND the fix handles the general case). AC#3 closes when this run's arc fleet constructs fixtures and executes scenarios. Riding the same run: 228 AC#3 (rollback scenarios), 229 AC#3 (un-park scenario), and the full observation sweep (214/215/227/200/201/208/209/210/211) on FULL GREEN; promotion then closes 199/205/213 per protocol. Standing calibrations remain in force: a known cause is not a pass; a runtime-stability health-check failure on the un-park scenario is the OLD chronic issue as its own new ticket, never a reopen of 229; no coin-toss re-runs.
---
<!-- COMMENTS:END -->
