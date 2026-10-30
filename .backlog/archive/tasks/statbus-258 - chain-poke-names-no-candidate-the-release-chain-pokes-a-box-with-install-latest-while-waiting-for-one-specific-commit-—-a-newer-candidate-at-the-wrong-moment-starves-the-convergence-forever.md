---
id: STATBUS-258
title: >-
  chain-poke-names-no-candidate: the release chain pokes a box with "install
  latest" while waiting for one specific commit — a newer candidate at the wrong
  moment starves the convergence forever
status: Done
assignee:
  - '@architect'
created_date: '2026-08-19 19:14'
updated_date: '2026-08-27 13:50'
labels:
  - release
  - upgrade
dependencies: []
priority: medium
type: bug
ordinal: 251000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
The dev-canary leg of the release chain (STATBUS-247, landed with C1 4324f1d3a) points dev's deploy branch at the candidate's commit and pokes the box via `./sb upgrade apply-latest` — but apply-latest resolves THE LATEST tag on the channel, not the commit the chain just pushed. If a newer RC exists at that moment (two cuts in flight, or a fix release tagged during the window), the box installs the newer one while the chain polls for convergence on the older one — and the convergence never arrives. The chain then reds (or hangs) on a box that is actually healthy and newer than requested.

Same defect family as STATBUS-256: a mechanism addressing "latest" where the contract is a SPECIFIC candidate. The architect flagged it during the 2026-08-19 dev-down incident review; it cannot bite on the first cut (the pushed candidate IS the newest) but becomes live the first time two candidates overlap.

THE FIX SHAPE (to be designed, not assumed): the poke should carry the candidate identity (commit SHA per canonical-commit-naming) and the box should install exactly that — register+schedule of a named target, not apply-latest — OR the chain's convergence check should accept "box is at the poked commit OR a descendant candidate on the same channel" with the reason logged. The first shape is preferred (candidate-addressed, matching STATBUS-244's ruling that only named candidates reach installations).

WHAT IS ACHIEVED: the chain's convergence poll can never be starved by a concurrent newer candidate, and a box never installs something other than what the chain believes it is testing.
<!-- SECTION:DESCRIPTION:END -->

## Comments

<!-- COMMENTS:BEGIN -->
author: foreman
created: 2026-08-19 19:52
---
Assigned to the architect for design (dispatched 2026-08-19 post-cut). The approval unit is the architect's concrete design comment; the King reviews that, not a general direction. Context for the design: v2026.08.0-rc.08 was just cut — the chain's first live run is in progress, and this cut is the safe case (the pushed candidate IS the newest). The fix must land before two candidates can overlap.
---

author: architect
created: 2026-08-19 19:53
---
DESIGN, part 1 of 2 — what the mechanism actually does, which is worse than the ticket states, and which of the two shapes survives it.

## THE PROBLEM IS NOT A HANG. IT IS A GREEN THAT REPORTS ON A DIFFERENT QUESTION.

I expected the poll to wait forever for a commit the box never installed. It does not, and the truth is sharper.

`deploy-to-dev.yaml:85-94` captures apply-latest's stdout and takes the commit **from apply-latest's own `deployed_commit=` emit** — the commit the BOX resolved — then polls `ci-deploy-status.sh` for **that** (:100-102, :138). So the convergence check asks:

> *did the box converge on whatever the box decided to install?*

That is very nearly self-referential. It cannot hang, and it cannot fail for the reason we care about. **If a newer candidate exists when the poke lands, apply-latest installs the newer one, the poll confirms the newer one converged, and `deploy-to-dev` reports SUCCESS — while the chain believes dev took the candidate under test.**

That is the zero-scope family exactly: a green reporting on an examination it did perform, but not the one it claims. The promotion gate would still refuse later, because it looks for a completed upgrade at the candidate's own commit and would not find one — so the **safety** holds. What breaks is the signal, and it breaks in the direction that costs a debugging session: the chain says dev took it, the gate says it did not, and the two disagree with no line of output explaining why.

## SHAPE (b) IS NOT VIABLE. IT WOULD FORMALISE THE DEFECT.

Accepting poked-commit-or-descendant treats "the box installed something newer" as success. That is not a loosened tolerance, it is a decision to call testing-something-else a pass — the precise thing STATBUS-249 exists to remove one layer up, and it contradicts STATBUS-244's rule that only a named candidate reaches an installation.

**Shape (a): the poke names the candidate.**

## THE CONSTRAINT THAT DECIDES THE IMPLEMENTATION: the allowlist is byte-pinned

The remote command is not free-form. `ops/niue/sshdoers` pins the exact byte-string, and both call sites say so at the line (`deploy-to-dev.yaml:56-58`, and the poll at :129-131 warns explicitly *"it must match the sshdo-pinned byte-string exactly. Do NOT change it to $HOME."*). So the fix is not "pass an argument" — **it is a new allowlist entry, which needs root on the box.**

That rules out chaining `register && schedule` over one ssh: two commands with a shell operator is not an allowlistable byte-string of the shape sshdo already uses, and it would need the shell to be permitted rather than a command.

**So the design is a single new verb taking one argument**, matching the pattern `ci-deploy-status.sh <40hex>` already establishes: one command, one pinned argument shape.

## COST, and it is much smaller than it first looks

Only **chain-driven** slots need this, and there is exactly one: **dev**. Norway is human-installed (STATBUS-247), demo is channel-following with its own trigger (STATBUS-248), and the country slots are opt-in human under the King's amendment. So this is **one new verb plus one allowlist line on one box** — not a fleet-wide allowlist rollout.
---

author: architect
created: 2026-08-19 19:53
---
DESIGN, part 2 of 2 — the concrete change, piece by piece.

## 1. NEW VERB — `./sb upgrade apply <commit>` (cli/cmd/upgrade.go)

One command, one argument, candidate-addressed. It does what `apply-latest` does **minus the resolution step**: register the named target, schedule it, and emit `deployed_commit=<40hex>`.

It should be a thin sibling of `upgradeApplyLatestCmd` (cli/cmd/upgrade.go:155), reusing the same register→schedule sequence (:298-302) and the same `deployedCommitLine` emitter (:151). The only difference is where the target comes from: an argument instead of `ResolveChannelToLatestTag`. Everything downstream — the already-converged skip (`decideApplyLatest`), the staleness self-heal annotation, `RunSchedule` carrying `recreate` — is unchanged and must stay shared, not copied.

Accept the same target shapes `register` already accepts (tag, 8-char short, 40-hex full — upgrade.go:77-79), because `resolveUpgradeTarget` already exists and the chain will pass a 40-hex.

## 2. THE CHAIN'S POKE (.github/workflows/deploy-to-dev.yaml:88)

`./sb upgrade apply-latest` → `./sb upgrade apply <sha>`, where `<sha>` is the commit the chain pushed to the deploy branch — the one it already has, and already believes it is testing.

## 3. THE EMIT BECOMES A GUARD, NOT A SOURCE (deploy-to-dev.yaml:94)

Keep the `deployed_commit=` capture, but **stop using it as the poll's input**. The poll must use the SHA the chain REQUESTED. Then assert the two are equal, and **fail loudly if they differ**.

This is the piece that turns a self-referential check into a real one. Under candidate-addressing they can only differ if something resolved a target other than the one asked for — which is the very defect this entry removes, so it must be an error rather than a silent preference for whichever value happens to be at hand. It costs one comparison and it is the only thing standing between us and the same class returning through a future change to resolution.

## 4. THE ALLOWLIST (ops/niue/sshdoers, dev's entries)

One new line permitting `~/statbus/... upgrade apply <40hex>`, pinned in the same shape as the existing `ci-deploy-status.sh <40hex>` entry. **Root access, so it belongs in the King's next root session** — the same session already holding the STATBUS-253 removals.

**Two ordering facts that must travel with it:**
- The allowlist line must land **before** the workflow change, or the poke is refused by sshdo and dev takes nothing at all. Workflow-before-allowlist breaks the canary outright.
- **`apply-latest` must NOT be removed from the allowlist.** Demo's auto-apply trigger (STATBUS-248) depends on that exact byte-string, and demo genuinely wants latest-on-channel — that is the correct verb for a channel-following box. Only dev stops using it.

## WHAT IS DELIBERATELY NOT SPECIFIED

- **Whether the other slots' deploy workflows move.** et/jo/ma/tcc/ug still poke with apply-latest, and under the King's amendment they are opt-in human anyway; their deploy workflows are already queued for deletion behind the Wave D channel confirmation. Changing them here would be work on machinery we intend to remove.
- **Whether `apply-latest` should eventually take an optional target and collapse the two verbs.** Plausible, but it would change an existing allowlisted byte-string's meaning, and a verb whose behaviour depends on argument presence is exactly the shape that produced this ticket. Two verbs that each do one thing is the safer vocabulary; revisit only if a second caller ever wants the choice.
- **Test shape.** The builder should pin that the poke names a commit and that emit≠request fails, but I am not prescribing the mechanism — the recent units have chosen better oracles than I would have specified.

## WHAT IS ACHIEVED

The chain stops asking a box whether it did what it chose, and starts asking whether it did what the chain requested. After this, a `deploy-to-dev` green means the candidate under test is installed on dev — which is what everyone already reads it as meaning.
---

author: architect
created: 2026-08-19 20:05
---
REVISED DESIGN, part 1 of 2 — the King is right, but not for the reason offered, and one hazard in the pull shape would destroy a production box if missed.

## FIRST, TWO CORRECTIONS TO THE FRAME (verified, not inherited)

**(b) is half wrong.** My push design does not grow a dependent on apparatus scheduled to die: STATBUS-244 explicitly KEEPS dev's deploy branch and `deploy-to-dev` as STATBUS-247's transport — my own ruling, and the reason I insisted 244b hold `master-to-dev` until 247 landed. What IS dying is the push path for demo, Norway and the country slots. So the objection is not "you are building on a corpse"; it is narrower and it still stands: **the deploy KEY that `deploy-to-dev` rides is what STATBUS-253 is removing**, and a new allowlist verb makes dev a second reason that key must survive.

**"Allowlists are unprincipled" is not quite the right diagnosis either.** A byte-limited allowlist is the *correct* shape for an inbound CI credential — it is the least-privilege form of a door that must exist. What is genuinely unprincipled is the pair the foreman found: **`/etc/sshdoers` is hand-managed root state with no sync to its repo copy** (its own header says *Managed by hand*), so the fleet's access policy is the one thing in this system that does NOT ship as code. That is a real violation and it is worth its own ticket regardless of which shape 258 takes.

## THE RULING: PULL, and the strongest argument is not about doors

Every other box in the fleet now acts on its own and is observed. Norway pulls and a human acts. Demo pulls on a channel. Country slots pull and a human opts in. **Dev pushing is the last remaining exception, and it exists only because I ruled in 247 that the chain needs a SYNCHRONOUS verdict** — an argument that was correct *given discover-only*, where the box would never act and the chain would have nothing to wait on.

The role gate changes that premise. If a canary-role box's own service schedules what it discovers, the chain has something to wait on **without acting on the box at all** — and dev becomes the same shape as every other installation, which is the campaign's north star rather than a concession to it.

**And the door argument should be stated precisely, because pull does NOT remove the door.** The chain still has to read dev's fate. What changes is the size of the grant: from **"install what I name"** to **"tell me what happened."** A read-only status query is a categorically smaller privilege than a remote install trigger, and it is the honest form of the King's objection — not *remove the allowlist*, but *stop granting mutation through it*.

## THE FULLY-PRINCIPLED END STATE ALREADY EXISTS IN THE PRODUCT

`UPGRADE_CALLBACK` (STATBUS-131, config.go:428-435) already fires **outbound** on every upgrade event — `completed`, `parked`, `rollback_failed`, `backup_failed` (service.go:6128, 7930, 8646, 7987). Those are precisely the fates the chain needs.

A box that reports its own outcome outward needs **no inbound door at all**. I am not specifying that as this ticket's build — it needs a landing place for the reports and that is new surface — but it should be recorded as the direction, so the read-only door is understood as a way-station rather than a destination.
---

author: architect
created: 2026-08-19 20:06
---
REVISED DESIGN, part 2 of 2 — the concrete pull design, the hazard that must not be missed, and the two things pull costs us.

## ⚠ THE HAZARD: "canary" IS TWO OPPOSITE ROLES, AND CONFLATING THEM SILENTLY AUTO-INSTALLS ON A PRODUCTION NSO BOX

STATBUS-254's role set is `production | canary | development`. Under pull, `canary` would gate auto-scheduling — and **Norway is a canary too.** Norway is a real production installation for a statistical office whose entire value is that **a person** performs each install against an observation card (STATBUS-247).

If Norway carries `UPGRADE_ROLE=canary` and canary means auto-schedule, **Norway silently begins auto-installing release candidates** — destroying the human gate, and doing it to the one box where the operator surface is the thing under test. Nothing would fail; the release would simply get quieter, which is this campaign's signature failure mode.

**So the role vocabulary must distinguish them before any auto-schedule ships.** Dev and Norway are not the same role and never were; calling both "canary" was loose from the start. Two values, named for what the box DOES rather than what we call it:

- **`canary-auto`** — the box installs each candidate on its channel itself. Dev, and only dev.
- **`canary-human`** — the box is offered candidates and a person installs them. Norway.

This is a change to a design the King has already seen, and it is the cost of the pull shape. I judge it worth paying because it makes an existing distinction explicit rather than inventing one — but it must land BEFORE the auto-schedule, not with it.

## THE DISCOVER-ONLY INVARIANT — ruled explicitly, since I defended it this morning

This morning I ruled that prerelease-on-dev is harmless **because discovery can never install**. Pull breaks that literally, so the invariant must be restated rather than quietly dropped:

> **A box never installs anything it was not configured to install automatically.** For every role except `canary-auto`, discovery offers and never schedules — unchanged, and that is what keeps production boxes, Norway and the country slots safe.

The guarantee was never "the code cannot schedule"; it was "no box installs without a deliberate act." Declaring `canary-auto` **is** that deliberate act, made once in config instead of repeatedly by a human. STATBUS-254's derive-mechanism is what makes this safe to rely on: role is explicit, recomputed, and **refuses on absent or unknown** — so a box cannot drift into auto-installing.

## THE CONCRETE DESIGN

1. **Role split** (STATBUS-254): `canary` → `canary-auto` | `canary-human`. Ships first, alone.
2. **Role-gated auto-schedule** in the service's discovery path: after `upsertCandidate`, if role is `canary-auto` AND the candidate is newer than installed AND nothing is in progress, schedule it. Guarded by the existing single-scheduled and single-in-progress uniqueness constraints, so concurrency is already handled by the database rather than by new logic.
3. **The chain stops poking.** `deploy-to-dev`'s apply-latest call goes. The chain OBSERVES: for candidate X, what is its fate on dev?
4. **The read stays over the existing status door**, unchanged in shape — `ci-deploy-status.sh <40hex>` — but now it is the ONLY grant dev's CI key carries. That is the principled improvement: the door shrinks from mutation to observation.
5. **Fates are the upgrade table's own vocabulary**: `completed` → green; `failed`/`rolled_back`/parked → red with the box's reason; **`superseded` → the chain is superseded** (STATBUS-246's named third verdict). **The starvation defect dissolves into a true named outcome instead of a lie** — which is the deepest argument for pull and the one I would put to the King first.

## WHAT PULL COSTS, stated honestly rather than discovered later

**We lose fail-fast on a dead box, and today proved that is not theoretical.** Under push, an SSH to a stopped dev fails in seconds and loudly. Under pull, a dev whose upgrade service is stopped produces **no fate at all**, and the chain waits. This morning's incident is the live evidence.

Mitigation is required, not optional: a **bounded wait that fails with a diagnosis**, naming the likely cause — *"dev has not acted on this candidate in N minutes; is its upgrade service running?"* Never a timeout that ages into a pass, and never a bare timeout either.

**And latency**: the box acts on its own tick (5 min on dev) rather than instantly. Acceptable against an install that takes minutes anyway, and it is the same latency every real customer has — which is the point.

## WHAT I AM DELIBERATELY NOT SPECIFYING

The callback-based outbound reporting. It is the better end state and it removes the last door, but it needs a landing place the chain can read, and that is a new externally-reachable surface which deserves its own design and its own King ruling rather than riding in here.
---

author: architect
created: 2026-08-19 20:19
---
RULING (round 3, supersedes the pull design in #4-#5). The King is right and my round-two reasoning was wrong in a way worth naming precisely.

## MY ERROR: I MOVED POLICY INTO THE PRODUCT TO AVOID A DOOR

Pull put auto-install code into **every StatBus installation in the world**, gated on a config value, so that ONE box of ours could be driven without an inbound grant. That trades a bounded local risk for an unbounded global one: an NSO that copies a config, or fat-fingers a role, gets a production statistical register auto-installing release candidates.

And the Norway hazard I flagged in #5 was not an independent problem — it was **the symptom**. The role vocabulary only strained because I was pushing our fleet's topology into the product's config. It evaporates with the pull design, and that is the tell: a hazard that disappears when you withdraw a design was created by that design.

**The test I should have applied, and will from now on:** *would an operator who has never heard of our fleet want this part?* `apply <commit>` passes — every operator wants to install exactly one named version. `auto-install-because-your-role-says-so` fails — nobody outside our arrangement wants it, and everybody carries its risk.

**So round one's shape stands: one general verb, zero product policy, no role semantics, no auto-install in any binary.** Its real sin was never the door — it was that the door's policy was hand-managed root state. **STATBUS-259 fixes exactly that and becomes a PREREQUISITE**, not a parallel nicety. A governed door whose policy ships as code is a principled mechanism; the same door managed by hand is not. That distinction, not push-versus-pull, was the thing to fix.

And his root point on 253 is correct: **re-examine the removal plan rather than invent around it.** Demo's trigger already proves the fleet needs an inbound door today. The answer is one well-governed door, not new mechanisms grown to avoid touching a plan made on a premise that turned out false.

## STATBUS-260 CHANGES THE TRANSPORT, FOR THE BETTER

The relay is broken by construction: a `GITHUB_TOKEN` push cannot trigger `on: push` workflows, so `deploy-to-dev` never fired and the orchestrator's comment at :457 asserts a false premise. That is not a reason to patch the token — **it is a reason to stop depending on an implicit trigger at all.**

**The chain should DISPATCH `deploy-to-dev` with the candidate's SHA as an input**, the same mechanism it already uses for the fleets. That is strictly better than repairing the relay: it needs no new credential, it removes a subtle platform behaviour from the critical path, and it makes the transport **explicitly candidate-addressed** — the chain names the commit rather than hoping a branch push implies it.

The composition is then clean, and every part is one that already exists or is genuinely general:

> chain dispatches `deploy-to-dev(sha)` → `deploy-to-dev` runs `./sb upgrade apply <sha>` through the governed door → poll uses the REQUESTED sha → guard asserts emit == request.

Note the consequence: with the SHA carried by the dispatch, **dev's deploy branch is no longer the trigger**. I am not ruling it removed — `deploy-to-dev` may still check it out, and 244 leaned on it — but it stops being load-bearing as transport, and that should be stated rather than left as a second half-live mechanism.

## WHAT SURVIVES FROM THE PULL DESIGN

**The requested-vs-deployed guard survives unchanged and is transport-independent** — poll for what was requested, assert the emit matches, fail loudly if not. It is what turns a self-referential check into a real one, and it was always the core of this ticket.

**Supersede-as-a-named-outcome survives too, in the chain's REPORTING rather than in product behaviour.** The chain can read the box's row state and report `superseded` truthfully (STATBUS-246's third verdict) without any binary anywhere auto-installing anything. Observation is general; auto-install was not.

## INTERIM: YES, DISPATCH `deploy-to-dev` MANUALLY TONIGHT — AFTER the failure mode is captured

The capture comes first: 260's evidence is worth more than an hour of dev's time, and it is STATBUS-247's first real lesson. Once captured, dispatch by hand through the existing `workflow_dispatch` door.

It is safe on this cut for the reason already on record: rc.08 IS the newest candidate, so `apply-latest` resolves it correctly. **That safety is a property of tonight, not of the mechanism** — which is precisely why this ticket exists. Confirm dev's upgrade service is running first (this morning's repair), or the dispatch lands on nothing.

## NOT SPECIFIED

Whether `deploy-to-dev` keeps its branch checkout, and the callback-based no-door end state — both real, both deserving their own entries rather than riding this one.
---

author: foreman
created: 2026-08-19 20:35
---
KING RATIFIED 2026-08-19 evening: the round-3 Lego design (comment #6) is APPROVED — his words: 'we go back to a Lego-based approach, and that is approved... the ratification of your new plan after my pushback, where you took my pushback into consideration, and the architect agreed.' TWO FURTHER RULINGS the same sitting: (1) NO WORKAROUNDS — the offered options of manually dispatching deploy-to-dev to rescue tonight's run, or waiting out the timeout as observation, were both rejected as workarounds; the principled path chosen: let tonight's run fail honestly, fix everything in code, and prove the fixed chain on the NEXT candidate with zero hands. (2) NO NEW CANDIDATE until everything is fixed in a principled manner — 'when I wake up and things are fixed in a principled manner, then I will cut a release candidate... or a release.' Overnight execution: engineer builds the verb + requested-vs-deployed guard + explicit candidate-addressed dispatch (STATBUS-260's fix); architect designs 259's ships-as-code mechanism (the prerequisite) and reviews every diff; tonight's orchestrator timeout (~21:33 UTC, BUDGET=4800 at release-fleet-orchestrator.yaml:474) stands as the true first-run record.
---

author: engineer
created: 2026-08-19 20:40
---
**UNIT 1 BUILT AND FROZEN — `./sb upgrade apply <target>`.** Chain: build OK, `go test ./...` green, `golangci-lint run ./...` 0 issues, gofmt clean. Files: `cli/internal/upgrade/apply.go` (new), `apply_test.go` (new), `cli/internal/upgrade/service.go`, `cli/cmd/upgrade.go`, `cli/internal/upgrade/schedule_require_register_test.go`.

**The purpose in two sentences.** The product could already install a named version — but only as two commands an operator had to know to pair, in an order that fails if you get it wrong. So callers reached for `apply-latest` instead, which installs whatever is NEWEST rather than what was asked for, and that is how a chain waiting on one specific commit gets handed a different one.

**IT COMPOSES, IT DOES NOT REIMPLEMENT — and that is the load-bearing part.** `registerStep` carries the STATBUS-169 tag↔commit write-guard and the `ensureCommitLocal` fetch; `scheduleStep` carries the parked-row carve-out and the atomic recovery-budget reset. A hand-rolled INSERT/UPDATE in `apply` would silently lack all of it and would look entirely correct in review, so a test forbids any direct write to `public.upgrade` in this function.

To compose them I split each existing command into a `…Step` (the body) and a thin `Run…` wrapper (the one-shot connection). Apply then runs BOTH steps inside a SINGLE connection — pinned, because two would leave a registered-but-unscheduled window: a state visible in `upgrade list` that no other product path produces and that an operator would reasonably act on.

**Registration is UNCONDITIONAL**, not guarded by "is it already registered?". `registerStep` is idempotent, so the guard would buy nothing and would cost the property an operator relies on when repeating a command after a failure: that `apply` behaves identically whether or not the box has seen this candidate.

**It stays GENERAL — the architect's test, pinned as a test.** A check fails if the function ever references a role, a channel, `ResolveChannelToLatestTag`, or one of our box names. The moment it learns any of those it stops being the general verb and becomes our deployment script wearing a product command's name.

**Refusals name each distinct cause and its own action** — wrong vocabulary, commit not on the box yet, and assets not published. That last one is emphasised as a WAIT rather than an error, with "nothing is lost by waiting", because an operator who reads the existing visible-wait path as a failure goes hunting for a problem that does not exist. On success the command says what it set in motion (backup → migrate → restart → health-check → rollback on failure) and how to follow it, since "scheduled" is not "installed".

**Six REDs, mutation site asserted on each:** reimplementing instead of composing; leaking a channel into the general verb; opening a second connection; making registration conditional; plus the two below.

**ONE EXISTING GUARD RETARGETED, DELIBERATELY.** Moving the scheduling UPDATE into `scheduleStep` left `TestRunSchedule_CommitAuthoritative_FailLoud_STATBUS169` reading a three-line wrapper — it would have examined nothing and PASSED, the zero-scope shape. It now reads `scheduleStep`, with every assertion unchanged and only the subject moved, plus a new assertion that `RunSchedule` still delegates there — so the guard cannot end up reading a function nothing calls. RED-verified both ways: re-introducing a tag-as-selector still fires it, and breaking the delegation fires the new one.

Starting unit 2 (STATBUS-260, the transport fix).
---

author: foreman
created: 2026-08-19 20:44
---
UNIT 1 LANDED as 35e572010 (architect verdict LAND, nothing to fold — their standout: the generality principle made mechanical, TestApplyIsGeneral_STATBUS258 reddening on any future channel/role/box-name reference with a failure message that teaches). Composed in one connection via the Step/Run split; direct-table-write forbidden by test; deployed_commit= emitted at the CLI layer (CI-facing contract kept out of the general internals); omission announced with its cost. Commit build+vet verified in an isolated worktree. Remaining for this ticket: unit 2 (explicit candidate-addressed dispatch + requested-vs-deployed guard, building now) and the allowlist line via 259's mechanism.
---
<!-- COMMENTS:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Chain poke names no candidate (dispatch layer landed ce1b48442, allowlist entered bdc546386, 2026-08-19): ./sb upgrade apply <sha> replaces apply-latest on dev, door permits named-target install, convergence poll asserts requested==deployed. Acceptance run 33075841334 green. King's principal fix ruling satisfied.
<!-- SECTION:FINAL_SUMMARY:END -->
