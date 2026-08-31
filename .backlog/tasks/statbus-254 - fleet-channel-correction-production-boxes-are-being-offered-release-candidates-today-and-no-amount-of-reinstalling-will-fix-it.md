---
id: STATBUS-254
title: >-
  fleet-channel-correction: production boxes are being offered release
  candidates today, and no amount of reinstalling will fix it
status: Done
assignee: []
created_date: '2026-08-19 10:27'
updated_date: '2026-08-31 11:23'
labels:
  - ops
  - release
  - upgrade
dependencies: []
references:
  - cli/internal/config/config.go
  - cli/internal/dotenv/dotenv.go
  - ops/create-new-statbus-installation.sh
priority: high
type: bug
ordinal: 247000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
NORTH STAR: a production box on the stable channel is never shown a release candidate as if it were installable. Today five are — and nothing done ON the boxes can fix it; the first stable cut is the resolution.

THE PREMISE, RE-VERIFIED AGAINST LIVE EVIDENCE (tester's read-only audit 2026-08-29, architect-ruled): all five production slots (et, jo, ma, tcc, ug) carry UPGRADE_CHANNEL=stable, yet their candidate lists contain ONLY release candidates — v2026.08.0-rc.17 registered as "available, discovered 2026-08-29", the day of the audit. A working stable filter applied to a release set containing zero stables (GitHub holds 30 releases, all pre-release) registers NOTHING; rc.17 being discovered onto these boxes proves NO channel filter ran. The boxes run binaries older than 291's channel filter and 311's CLI channel fix, so their discovery has nothing to filter with.

THE LIVE EXPOSURE is the human path, not the automatic one: RCs have sat "available" without ever becoming "scheduled" (evidence, not proof, that these binary eras offer rather than install) — but `./sb upgrade schedule <rc>` remains executable by an operator looking at a list that appears to sanction it. This is field confirmation of 291's "the list IS the offer" ruling, now observed on five live NSO installations.

WHY NO ACTION ON THE BOXES CAN CLEAR IT (the finding this ticket must carry): the fix can only reach those boxes through an upgrade, and the only upgrades on offer are the very RCs they should not take. 291's filter and 311's fix are newer than anything the fleet runs — nothing on the boxes can be repaired by acting on the boxes. THE RESOLUTION PATH IS THE FIRST STABLE CUT: it simultaneously clears the offers (a stable-channel box finally has a legitimate target) and delivers the filter that prevents recurrence. That is the actual resolution, not a workaround.

INTERIM MITIGATION — operational only, stated plainly because no mechanical guard exists: changing the boxes requires an upgrade (circular), and dismissing the rows would be a manual DB write (forbidden on any environment). The operators of those five slots should not act on an RC offer before the first stable lands.

EXPLICITLY REJECTED — do not re-propose: marking an RC as a stable release on GitHub. It would make an unpromoted candidate indistinguishable from a promoted one for the ENTIRE fleet — every box with a WORKING filter would then correctly install an unvalidated candidate, converting a display problem into a fleet-wide installation event.

REMAINING WORK: (1) one read per box distinguishing the filterless mechanism for the record (pre-channel-concept binary vs 291-defect-era binary — binary version against 254's and 291's commits; changes neither remedy nor risk); (2) at the first stable: verify each box's discovery clears the RC offers and converges to the stable, then close.

WHAT IS ACHIEVED: the exposure is named and bounded, the resolution rides the release that was coming anyway, and the recurrence is prevented by the filter that release carries.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 The live exposure is confirmed per box before and after: each box's channel is read from the box, never inferred from the default or from this ticket
- [x] #2 Five NSO installations and demo are on the stable channel; dev is on the channel its canary role requires
- [x] #3 The correction reaches every box through code plus the box's own install — no per-box SSH mutation, unless the alternative is explicitly chosen and recorded here
- [x] #4 The channel is derived from the box's role on every config generate, so a stale value cannot survive a reinstall and a future default change reaches the whole fleet
- [x] #5 A box whose declared role and channel disagree reports it loudly rather than silently choosing either
- [ ] #6 This lands before the per-slot deploy workflows for et/jo/ma/tcc/ug are deleted — no box loses its only receive path while still misconfigured
- [x] #7 The first-writer-wins behaviour is recorded where the next person would otherwise trust config generate to fix a setting
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
**Era read complete (tester, 2026-08-29): the filterless mechanism is PRE-CHANNEL-CONCEPT on all six boxes** — et, jo, ma, tcc, ug AND demo all run v2026.07.0-rc.03 (commit 111546ee), a July binary predating both 291's filter (a4ac7ca81) and the durable role mechanism (733b0df4d). Not the 291-defect era — no selection logic exists at all in what they run; UPGRADE_CHANNEL=stable is correct intent with nothing to apply it. At the first stable: the new binary carries the filter AND the one-time channel→role translation, so each box converts to UPGRADE_ROLE=production and the RC offers clear — the two closure observables (comment #12) then complete, and the translation code deletes per its own marker.
<!-- SECTION:NOTES:END -->

## Comments

<!-- COMMENTS:BEGIN -->
author: foreman
created: 2026-08-19 11:23
---
KING RULED 2026-08-19 (third decision of the sitting): the fleet correction executes NOW as the config-change-and-regenerate path — 'it's just a configuration change and a regenerate; nothing big, nothing drastic, nothing we're removing.' That is the alternative this entry honestly named, chosen by him with the cost known. The derive-the-channel-from-role mechanism (this entry's main design) STILL FOLLOWS as the durable fix — the ruling changes the sequencing (correct the live fleet immediately, fix the mechanism after), not the destination. Execution: architect specifies the exact per-box command sequence (product tooling only); operator runs it verbatim; et/jo/ma/tcc/ug + demo → stable first, dev → prerelease last, read-back verification per box. His flow context: the next candidate cut follows the 240 landing, so the corrected channels meet the rebuilt chain on its first live run.
---

author: architect (pinned by foreman)
created: 2026-08-19 11:25
---
EXECUTION COMMAND LIST (verified at source before dispatch): the six-step per-box sequence — read-before (grep + explicit exit), ./sb dotenv -f .env.config set UPGRADE_CHANNEL <target>, ./sb config generate, systemctl --user restart statbus-upgrade@$USER, verify the RUNNING service's channel= line via journalctl, verify the offer set via ./sb upgrade list. THE LOAD-BEARING FINDING: A RESTART IS REQUIRED — loadConfig() is called only from startup paths (LoadConfigAndConnect :1789, Run :1992), so the channel is cached in the daemon for its process lifetime; without the restart the file says stable while the running service keeps offering prereleases, and a grep of the file falsely confirms 'fixed' — the zero-scope shape arriving in an ops procedure, which is why verification reads the running service, never the file. Premises verified: config generate genuinely propagates .env.config → .env (config.go:771-778, not the first-writer trap one layer down); the unit is USER-level (no sudo needed — devops has none). Stop-conditions: unreadable file → stop that box; restart error → report, do not sudo; step-5 shows old channel → stop. One box at a time; et/jo/ma/tcc/ug/demo→stable first, dev→prerelease last; step-1/step-5 outputs recorded verbatim as AC#1's before/after evidence. Dispatched to the operator.
---

author: operator (pinned by foreman)
created: 2026-08-19 11:26
---
FLEET CORRECTION EXECUTED AND VERIFIED, all seven boxes, no stop-condition hit. Before/after evidence recorded verbatim (full log in tmp/agents/operator.md): et/jo/ma/tcc/ug/demo each read UPGRADE_CHANNEL=prerelease before → running service now logs 'Upgrade service started (channel=stable, interval=6h0m0s)'; dev read edge before → now 'channel=prerelease, interval=5m0s' (the 5-minute interval consistent with its canary role). Every verification read the RUNNING service's startup line, not the file, per the procedure's load-bearing finding. AC#1 and AC#2 closed. AC#3's exception clause is satisfied as written — the alternative was explicitly chosen by the King and recorded in comment #1. REMAINING: AC#4/#5 (derive-from-role mechanism — the durable fix), AC#6 (sequencing guard for the deploy-workflow deletions, now trivially satisfied since the channels are correct), AC#7 (record first-writer-wins where the next person would trust config generate). The exposure this entry was filed for is CLOSED: no NSO production box is offered release candidates any more, and dev now follows the candidate channel its role requires.
---

author: architect
created: 2026-08-19 11:30
---
DURABLE-FIX DESIGN, part 1 of 2 — the shape, and the two objections it has to survive.

## Where the role is declared: a NEW key, and the alternatives are worse

A box already declares `DEPLOYMENT_SLOT_CODE` (:328) and `CADDY_DEPLOYMENT_MODE` (:347). Neither can carry this:

- **Mode is the wrong axis.** STATBUS-106 deliberately DECOUPLED the upgrade axis from the front-door mode. Re-coupling them here would undo a ruling, and it cannot express the case we actually have: Norway and an ordinary standalone share a mode and need different channels.
- **Slot code is a NAME, and deriving from it is disqualifying.** It would bake OUR fleet's names into a product that statistical offices install — a customer whose slot happened to be called `dev` would be treated as our canary. The product must not know about our boxes.

So: **`UPGRADE_ROLE` in `.env.config`**, on the upgrade axis, closed value set: `production` (default) | `canary` | `development`. `UPGRADE_CHANNEL` **leaves `.env.config` entirely** and becomes a generated output in `.env` only.

## OBJECTION 1, and it is the strongest one against my own recommendation: if role→channel is one-to-one, this is a rename

It is one-to-one today — `production`→stable, `canary`→prerelease, `development`→local — and a renamed key would drift exactly as the old one did. The answer is not that the mapping is complicated; it is **which of the two is a statement and which is a consequence**:

- The ROLE is a statement of intent. It should never change unless a human changes what the box is FOR. Remembering it is correct.
- The CHANNEL is a consequence of policy. When we change what production boxes follow — stable today, an LTS line tomorrow — **every box must pick that up**, and today none of them can.

So the win is not the mapping's shape, it is that the mapping becomes OURS TO CHANGE and the change reaches the fleet. That is precisely what failed here: the default moved on 2026-06-21 and not one box noticed. State this plainly in the code, because a reader who sees a 1:1 table will otherwise conclude the indirection is pointless.

## OBJECTION 2: is recomputing a value a standing self-heal, which is forbidden?

No, and the distinction is worth writing at the line. **A self-heal silently repairs someone's input. This makes the value stop being an input.** `.env` is a generated file already; nobody calls regenerating it self-healing. The channel simply moves into the generated tier where it always belonged, and there is nothing left to repair because there is nothing left to corrupt.

The test that keeps this honest: if an operator hand-sets `UPGRADE_CHANNEL` in `.env.config` — an input that no longer exists — config generate must **FAIL LOUDLY naming it**, neither silently honouring it nor silently ignoring it. That is AC#5's guard, and it is the loud-guard half the no-self-heal rule requires. The rule forbids quiet repair; it demands exactly this.
---

author: architect
created: 2026-08-19 11:30
---
DURABLE-FIX DESIGN, part 2 of 2 — how it meets the fleet we just corrected, the guard, and AC#7.

## THE CORRECTION BECOMES THE SEED — this is the part that must not be got wrong

All seven boxes now hold an **explicit** `UPGRADE_CHANNEL` in `.env.config` (comment #3). Under part 1's design that key is an input that no longer exists, so a naive rollout would make config generate **fail loudly on every box we just fixed** — the durable fix breaking the fleet the moment it lands.

The resolution turns that around: **a ONE-TIME translation, where the operator's correction is the input.** On a box with `UPGRADE_CHANNEL` present and no `UPGRADE_ROLE`, config generate:

1. infers the role from the channel (`stable`→production, `prerelease`→canary, `local`/`edge`→development), 
2. writes `UPGRADE_ROLE`,
3. REMOVES `UPGRADE_CHANNEL` from `.env.config`,
4. prints exactly what it did and why.

So the work the operator just performed is not fought — it is **read once and promoted into the durable form.** Every box lands on the role its corrected channel already implies, with no second per-box pass. And its first fleet-wide application is self-verifying: if the seven boxes come out as six `production` + one `canary`, the mechanism reproduced a state we independently established by hand, which is a stronger proof than any test.

**This translation is a ONE-TIME CORRECTION and must be removed once the fleet has run it** — the no-standing-self-heal rule applies to it exactly. It executes once per box, it is loud, and it carries its own removal note. What must NOT happen is it quietly surviving as a permanent compatibility shim; that would re-admit the very key we are removing, and internal code here ships as clean breaks.

## THE LOUD GUARD (AC#5), precisely

After the translation window, `UPGRADE_CHANNEL` in `.env.config` can only mean someone re-added it by hand. config generate must then **REFUSE**, naming: the key, the role currently declared, the channel that role derives, and the one action that resolves it (state the role you want, remove the key). Not a warning — a warning would be honoured-or-ignored ambiguously, and the operator would never learn which.

The symmetric case matters as much: an **unknown or absent** `UPGRADE_ROLE` must refuse too, rather than defaulting quietly. A box that silently defaults is exactly how five NSO installations sat on the wrong channel for two months without anyone being able to see it. **Absent-means-default is the mechanism that produced this ticket.**

## AC#7 — recorded as a MECHANISM, not a comment

Prose rots, and this hazard has already cost us once. Two parts:

1. **A pin** asserting `UPGRADE_CHANNEL` is never written through `Generate`/`gen()` — i.e. that this key is DERIVED, not defaulted. If someone reintroduces it into the set-if-absent tier, the mechanism this ticket exists to remove comes back and the test reddens naming why.
2. **A comment at `dotenv.Generate` itself** (dotenv.go:222) — the single place every future author meets this behaviour — saying plainly: *this preserves an existing value forever; a value that must follow policy has to be derived instead, and `UPGRADE_CHANNEL` is why we know that.* One sentence at the call site everyone passes through beats a paragraph in a doc nobody opens.

## What I am NOT specifying, deliberately

The role value set is closed but not final — whether an external customer eventually needs something between `production` and `canary` (an eager adopter tracking candidates deliberately) is a real question, and it should be answered when someone actually wants it rather than invented now. `canary` covers it today.
---

author: engineer
created: 2026-08-19 12:17
---
**DURABLE FIX BUILT AND FROZEN — deliberately NOT landed** (post-cut unit; it rides the next candidate after the tag). Built to the architect's pinned design in #4/#5. Chain: build OK, `go test ./...` green, `golangci-lint run ./...` 0 issues, `gofmt` clean on every touched file, `bash -n` clean on all four shell files. Part 1 of 2 — the mechanism; part 2 lists the consumers and the one fork.

**The purpose in two sentences.** Five statistical offices' production installations followed release candidates for two months because the channel was written once at box creation and nothing recomputed it. After this, a box declares what it IS and the channel is a computed consequence — so a policy change reaches the whole fleet on the next `./sb config generate`, and a stale value cannot survive a reinstall.

## The mechanism

`cli/internal/config/upgrade_role.go` (new) holds it as pure functions over a loaded `.env.config`, so every branch is unit-tested without touching a disk or a fleet. `ResolveUpgradeRole` runs four steps in a load-bearing order:

1. **TRANSLATE** — channel present, no role: infer the role, write it, REMOVE `UPGRADE_CHANNEL`, announce it. The operator's hand-correction of 2026-08-19 is not fought; it is read once and promoted into the durable form.
2. **SEED** — neither key: declare the default explicitly in `.env.config`, where an operator can read and change it.
3. **REFUSE a hand-added channel** — after step 1, a channel beside a role can only be hand-added. A refusal, not a warning: a warning is honoured-or-ignored ambiguously and the operator never learns which.
4. **VALIDATE** — an unknown role refuses. Unknown-means-default is the same defect as absent-means-default, and harder to see.

The translation carries its own removal note at the line: a ONE-TIME correction, not a compatibility shim. Leaving it in permanently re-admits the key this ticket removes.

**AC#7 as a mechanism, both halves.** A pin fails if `UPGRADE_CHANNEL` is ever written through the set-if-absent tier again or read back out of `.env.config`, with the five-installations reason in the failure text. And `dotenv.Generate` now carries the warning at the one place every future author passes through: this preserves a value forever; a value that must follow policy has to be derived; `UPGRADE_CHANNEL` is how we know.

## ONE DEVIATION FROM THE DESIGN, and it is an equivalence fix

The design names `production` as THE default. Applied flatly, that derives `stable` on every developer's machine, whose old default was `local` — silently switching their migration-fix behaviour from stop-for-a-human to auto-bless. Fixing a value that changed under boxes unnoticed, by changing a value under boxes unnoticed, would be a second instance of this exact defect.

So the SEEDED role is mode-aware: development mode → `development`, everything else → `production`. That reproduces the old channel exactly on both modes, and a test asserts the equivalence per mode. The mode is consulted ONCE, to seed — the role is never re-derived afterwards, so a later mode change cannot silently move a box, and a separate test pins that too.

## Tests, RED-verified by mutation

Four load-bearing pins, each confirmed to FAIL when its property is broken: reintroducing `gen("UPGRADE_CHANNEL", …)`; stripping the `dotenv.Generate` warning; making the hand-added-channel guard silently ignore; and flattening the seeded default to `production` (which reddens the equivalence test with the dev-machine regression named). Also covered: translation for all four legacy channel values, idempotence across two runs — a non-idempotent translation would fail every box on its SECOND config generate — and refusal texts asserted to be ACTIONABLE rather than merely present.
---

author: engineer
created: 2026-08-19 12:17
---
**Part 2 of 2 — the consumers, and the one fork reported rather than absorbed.**

## Consumers found and corrected — the design named the mechanism, not its dependents

- **`./sb upgrade channel` becomes `./sb upgrade role`** — a clean break, not a rename: the old command wrote a key that its own next step (config generate) would now refuse. While rewriting it I found and fixed a live bug in it: the restart used `systemctl` WITHOUT `--user`, so on a devops account with no sudo the "not fatal" branch was the NORMAL path — the command reported success having never restarted the daemon, leaving the running service on the old channel. It now uses `--user` per the architect's verified finding, and when the restart does fail it says plainly that THE RUNNING SERVICE IS STILL ON THE OLD CHANNEL.
- **`ops/create-new-statbus-installation.sh`** declares `UPGRADE_ROLE=production`. Its old write was `sed -i "s/UPGRADE_CHANNEL=.*/…/"`, which only works when the key ALREADY exists — on a box without it, it printed "Set …" while writing nothing. The role write handles both cases. The interim "no stable release exists yet → prerelease" branch is removed: what an ordinary installation follows is one fleet-wide policy decision now, not a per-box setting. It is already dead in practice (stable tags exist), and the condition is still ANNOUNCED, so an operator learns the box may have nothing to install yet — and is told plainly that this is the correct state, not something to work around by moving the box to prerelease.
- **`cloud.sh` (3 sites)** read the channel from `.env.config` with a `|| echo "prerelease"` fallback. After this change that read always misses, so every box — including the five NSO installations — would be REPORTED as prerelease. They now read the generated `.env`, and the fallback is `unknown`: a wrong-but-believable answer here is precisely the failure this ticket exists to remove.
- **`test/install-recovery/lib/vm-bootstrap.sh`** declares the role, so the harness does not depend on a translation that is scheduled for deletion. While there I corrected a stale premise in the park arc's comment: it justified the VMs' channel from `CADDY_DEPLOYMENT_MODE=standalone`, but the harness authors `development` — the channel was stable only because the key was written explicitly. Now stated as the real mechanism.
- **`doc/CLOUD.md`, `doc/DEPLOYMENT.md`, `doc/upgrades.md`** instructed operators to set a key that now refuses. Rewritten to the role vocabulary. CLOUD.md's verification step now says to read the RUNNING service rather than the file, since the daemon loads config only at startup — the same load-bearing finding that governed the fleet correction.
- **the upgrade service's `loadConfig`**: a missing `UPGRADE_CHANNEL` in `.env` silently became `stable`. It still starts — a dead upgrade service is worse than a conservative one — but now WARNS, naming `./sb config generate`. That was the same invisible-wrong-channel failure, one layer down.
- **`release_canary.go`** pointed operators at `./sb upgrade channel` with no argument, which could only ever have errored (it required one). It now shows how to read the running service.

## THE FORK — the `edge` capability, reported rather than absorbed

The three-role set cannot express `edge`, and edge is live machinery today: `cloud.sh migrate-up` / `migrate-down` gate on it, `cmd/upgrade.go` branches on it to build from source rather than download a release, and `migrate.go` carries a dedicated `channelEdge` class for an always-latest box. With the channel no longer settable, no box can be put on edge, so those paths become unreachable. The ruled mapping (`edge`→development) also converts any box on edge to `local`, which is a real semantic change — unexposed today only because dev was moved to prerelease during the fleet correction.

I implemented the mapping exactly as ruled and did NOT delete the edge machinery. The docs now state plainly that no role derives edge, and point at `./sb upgrade register <commit>` + `schedule`, which reaches the same result for a single target. Whether edge deserves a fourth role or should be retired deliberately is a policy decision, not mine — and the table it lives in is one line, so either answer is cheap once ruled.

## Before landing

`cli/internal/upgrade/service.go` carries BOTH this unit's `loadConfig` warning and STATBUS-255's RunCheck switch. They sit in different functions, so splitting them is mechanical if the two units land separately.

AC#4, #5 and #7 are met by this build; AC#3 is met for every FUTURE correction (this one reached the fleet by the King's chosen alternative, recorded in #1). AC#6's sequencing still applies: this lands before the per-slot deploy workflows for et/jo/ma/tcc/ug are deleted.
---

author: foreman
created: 2026-08-19 12:23
---
KING RULED 2026-08-19: EDGE IS RETIRED — 'Yes, retire it.' Presented with the architect's reasoning (nothing uses the always-track-master channel; no box is on it since dev moved to prerelease; running a specific commit keeps working via register+schedule; a fourth role would exist only to keep unreachable machinery alive). The retirement diff is queued as post-tag unit #4, carrying the architect's non-negotiable instruction: migrate.go's channelEdge class governs migration-fix behaviour, so removing the edge branch MUST be verified not to shift another channel's classification through a fall-through — deleting a branch from a classifier is exactly where a neighbouring case silently changes meaning.
---

author: engineer
created: 2026-08-19 12:34
---
**EDGE RETIREMENT BUILT AND FROZEN** (King ruled 2026-08-19: "Yes, retire it") — post-tag unit #4, landing after the deletion diff. Part 1 of 2. Chain: build OK, `go test ./...` green, `golangci-lint run ./...` 0 issues, gofmt clean, `bash -n` + `shellcheck -S error` clean on `install.sh` and `cloud.sh`.

**The purpose:** no box follows master unattended any more. Running one SPECIFIC commit is untouched and still works exactly as before — `./sb upgrade register <commit>` then `schedule`. What retires is the autopilot.

## THE NON-NEGOTIABLE FIRST — the classifier, proven rather than argued

`migrationChannelClass` decides how a content_hash MISMATCH is handled: re-stamp trusting the cut gate (release), full rebuild (seed-build), or refuse and hand it to a human (localDev). The architect's warning was exact — deleting a branch from a classifier is where a neighbour silently changes meaning.

Two mechanisms were checked, not one. The obvious one: Go has no implicit fall-through and the arms test exact strings, so `stable`/`prerelease`/`seed-build` cannot be touched. **The non-obvious one, which is where the real hazard lived: the constants are `iota`, so removing `channelEdge` RENUMBERS every constant after it.** That is harmless ONLY because no value is ever persisted, serialized or compared numerically — established by enumerating every use before cutting, not assumed.

Outcome: a box with a stale `UPGRADE_CHANNEL=edge` now classifies `channelLocalDev` — human guidance, never an auto-redo and never an auto-bless. That is the safe direction, and it is why the classifier's default is localDev rather than release.

**RED-verified three ways, mutation site asserted each time:** making `seed-build` join release fires it; re-admitting `edge` as release (the dangerous direction — auto-bless on a box nobody chose) fires it; re-adding any edge branch fires the clean-break guard.

**Nothing is lost with the arm.** The STATBUS-166 content-recognition it held existed to heal dev's gate blocking every deploy while dev tracked master. Dev now follows prerelease, so it classifies `channelRelease` and the bless above covers the same mismatch — by trusting the cut gate directly, which is the stronger form of the same trust. Removing it also deleted a `MAX(version)` psql round-trip that ran on every migrate-up for a branch nothing reads any more.

## Two test expectations changed DELIBERATELY, not to make anything pass

`TestEdgeAndUnknownChannelsUnchanged` asserted edge resolves to `("", nil)`. That was CORRECT while edge existed — a box tracking master genuinely had no tag to resolve. Now the value can only arrive from a stale config, so silence is the wrong answer and it must error; the test says so and says why. Likewise `FilterTagsByChannel("edge")` now admits NOTHING rather than everything — the exclusive-allowlist shape means a stale value is offered no tag rather than every tag.

One guard was retargeted rather than weakened: `TestInstallShBranchNamesNamespaceFree` required three checkouts, one per install path, and the `origin/master` one was edge's. It now asserts the `--commit` path in its place, so the count still matches the number of real paths instead of silently shrinking.
---

author: engineer
created: 2026-08-19 12:34
---
**Edge retirement, part 2 of 2 — what else came out, and two live traps it exposed.**

## The rest of the removal

Resolution (edge no longer returns an empty tag — it ERRORS, because an empty tag reads downstream as "nothing to upgrade to" and would freeze a stale box silently); the tag allowlist; `discoverEdge` and its commit discovery; `apply-latest`'s build-from-source branch; `install.sh`'s edge branch and its `stable|prerelease|edge` validation; `release check --channel edge`; `cloud.sh`'s install strategy; and every doc mention — each rewritten to name `register` + `schedule` where edge's capability was described, so nobody reads a removal as a lost capability.

## TWO LIVE TRAPS the retirement exposed, both fixed

1. **`release check --channel edge` returned SUCCESS without checking anything.** A pass-without-examining is only ever correct while the thing it declines to examine truly does not exist — the zero-scope shape, sitting in a release-readiness gate. Now the channel refuses by name instead of quietly returning green.
2. **`install.sh`'s procurement refusal advised operators to "use --channel edge".** That text prints at a failure moment, and after the retirement it would have sent an operator to a channel that no longer exists. The advice now points at a released version. The build-fallback branch it belonged to went too: edge was its only caller (an UNPUSHED local master commit legitimately had no image), and a named commit always has one or is not ready to install — so the yes/no argument that selected it is gone and the deterministic path is the only path.

## The two retired cloud.sh commands

`cloud.sh migrate-up` / `migrate-down` are reduced to explicit refusals with their BODIES DELETED, not left behind a guard. Dead code under a refusal reads as "this could still be right", and this particular code would be reached for at exactly the wrong moment — on a production box, under pressure, by someone looking for a way to undo a migration. The refusals name the correct action instead: released migrations are immutable, so the fix is a FORWARD repair migration (AGENTS.md, STATBUS-172).

They were edge-only for a real reason, now written down where the refusal is: rolling a migration BACKWARDS is safe only where migrations are not immutable, and edge was the one channel applying ungated master commits.

## The interaction with the frozen derive-mechanism, handled as instructed

The translation's `edge`→development arm is KEPT, and is now the last mention of edge in the tree — deliberately. A box whose `.env.config` still carries `UPGRADE_CHANNEL=edge` is precisely what that one-time translation exists for: it must be read once and converted, or that box refuses on its next config generate holding a key it cannot legally have. Development is the right landing place, because what edge meant — follow whatever is newest, automatically — is the one thing no box does any more. It is annotated at the line so it is not tidied away by someone grepping for the word, and it still dies with the rest of the translation once the fleet has run it.

One further note for the record: `apiRuleOracle` in the STATBUS-255 deletion diff also still names edge, and should stay that way. It is a FIXED historical transcription of what the GitHub releases API path meant; editing it to match today's world would falsify the record it exists to preserve.

## Landing

Order unchanged: RunCheck switch → derive-mechanism → deletion diff → this retirement. This unit touches `migrate.go`, `github.go`, `service.go`, `cmd/upgrade.go`, `cmd/release.go`, three test files, `install.sh`, `cloud.sh`, and five docs.
---

author: engineer
created: 2026-08-19 12:48
---
**Zero-value pin FOLDED into the edge-retirement unit and re-frozen.** Chain: build OK, `go test ./...` green, `golangci-lint run ./internal/migrate/` 0 issues, gofmt clean.

The architect's generalisation is right and it is the half I stopped one step short of. I verified that renumbering the `iota` constants was SAFE; I did not notice that the retirement made a second property load-bearing — `channelLocalDev` is now the ZERO value, so anything reaching a classification without being assigned one gets the conservative branch.

**Why that matters and is not cosmetic:** the two branches are not symmetric. `channelLocalDev` REFUSES a changed migration and asks a human; `channelRelease` RE-STAMPS it, trusting the cut gate. A var declared and not assigned, a struct field never set, a future map lookup that misses — all land on whichever constant sits first. If a later tidy-up sorts the block alphabetically or promotes the "most common" case, an uninitialised classification silently starts meaning TRUST THE BLESS: an unvetted migration edit blessed on a production box, with nothing printed to say so, from a diff that reads as housekeeping.

**Encoded as the lesson, not the answer**, per the same move as the park-consumer classification: the assertion is that the ZERO VALUE MUST REMAIN THE CONSERVATIVE CLASSIFICATION, stated at the constant block and pinned by `TestZeroValueIsTheConservativeClassification`. Its failure text says what breaks and how to fix it, and it explicitly allows a reorder — provided the conservative case is still first. It also asserts the two classifications remain DISTINCT, since "conservative" means nothing if they collapse.

**RED-verified, mutation site asserted:** moving `channelRelease` to position zero fails the pin by name. (Note the failure prints "it is now 0" — correct and worth reading carefully: the zero VALUE is still 0, it is the MEANING that changed. The test compares against the named constant, not the number, which is why it catches a change that any numeric assertion would sail past.)
---

author: foreman
created: 2026-08-19 19:18
---
MECHANISM LANDED: 733b0df4d (derive channel from declared UPGRADE_ROLE; one-time translation seeds from the operator's corrected channels; hand-added channel and unknown role both REFUSE; AC#7's pin + dotenv.Generate warning in). Edge retirement landed as 1dff9c18f, carrying the zero-value pin (iota zero must remain the conservative classification, RED-verified) and the Release/Commit/CommitDetail type deletions per the architect's boundary rule. AC#6 satisfied by sequencing — the per-slot deploy workflows are still undeleted. TICKET STAYS OPEN for two observables: (1) the one-time translation actually running on the fleet (verifiable on each box's next upgrade: seven boxes must come out six production + one canary), then its removal per the no-standing-self-heal rule; (2) that removal itself.
---

author: foreman
created: 2026-08-19 19:18
---
DEV INCIDENT 2026-08-19, recorded here because it grew from this ticket's fleet correction: at 11:53:33 UTC dev's compose project was torn down (systemctl --user stop of the upgrade unit + compose down, volumes kept) by an agent session on the King's own machine — IP-verified — doing a stop-everything/change-config/start-everything cycle whose start half never ran; the transcript died with /clear so the exact session is unattributable. Our operator answered plainly: not them, reads only. REPAIRED 19:12 UTC via ./sb install (architect-ruled; a bare start-all would have left the upgrade unit stopped — a canary that looks alive and cannot take the release): all containers up, unit active, running service logs channel=prerelease interval=5m, front door 307. PROCESS RULE from the King, now in durable memory: any agent using box access must pre-declare its exact command list; this correction's six-step verified procedure is the model, the unrecorded stop-half is the anti-pattern.
---

author: foreman
created: 2026-08-20 06:40
---
DEV'S TRANSLATION CONFIRMED BY STATE (2026-08-20, after rc.09 converged on dev). Pure reads over the CI door:

.env.config: `UPGRADE_ROLE=canary` — and NO UPGRADE_CHANNEL line (the one-time translation removed it)
.env: `UPGRADE_CHANNEL=prerelease` — derived from the canary role on every generate

NOTE ON EVIDENCE FORM: the plan was to pin the translation NOTICE verbatim from rc.09's install logs, but the notice is one-time stdout at the run that converts, and on dev that run has already passed (journalctl 500-line history + tmp logs both empty of it — likely consumed during yesterday's repair install or the rc.09 install, unlogged). The durable evidence is the CONFIG STATE above, which is stronger anyway: it shows the translation's RESULT is in force, not merely that it was announced. For the remaining fleet boxes, the same two reads (role key present + channel key absent in .env.config) are the per-box evidence form; the notice is a bonus if a box's install log happens to be caught in time.

Dev leg: DONE. Remaining: the other fleet boxes translate as their own installs run; 254 closes (and the translation case in cli/internal/config/upgrade_role.go is DELETED, per its own >>> marker) once every box shows the role form.
---

author: operator (pinned by foreman)
created: 2026-08-27 19:44
---
FLEET READ 2026-08-27 (running service vs config intent, all ten boxes, read-only) — AND IT CORRECTS THIS TICKET'S PREMISE: no production box is being offered release candidates today. All six legacy production slots (demo, tcc, ma, ug, et, jo) run channel=stable in the LIVE service (evidence: 'Upgrade service started (channel=stable)' lines, all timestamped Aug 19 11:25-11:26 — the fleet correction event, still holding), via the OLD mechanism: UPGRADE_CHANNEL=stable set, UPGRADE_ROLE unset. Three boxes carry the durable mechanism correctly: dev (role=canary → prerelease), ua (role=production → stable, born-after-fix), no/rune (role=canary → prerelease). ONE NEW FINDING: test has UPGRADE_ROLE=production set but NO RUNNING UPGRADE SERVICE — config ready, service absent; cause unknown, investigation dispatched. REMAINING SCOPE therefore narrows to: (1) migrate six boxes from the legacy key to the role key — functional today but not durable (remove UPGRADE_CHANNEL without adding UPGRADE_ROLE and the box loses derivation); migration mechanism needs an architect ruling (hand config edits vs a loud one-time translation in config generate/install vs natural rewrite at next upgrade — mind the no-standing-self-heal rule); (2) test's dead service.
---

author: foreman
created: 2026-08-27 19:44
---
CORRECTION to comment #15's closing line — I re-derived a solved problem: NO migration ruling is needed. The one-time translation is ALREADY LANDED (733b0df4d, cli/internal/config/upgrade_role.go — channel-present/role-absent infers the role, writes it, REMOVES the legacy key, announces; comment #6), and dev already went through it (comment #14's config-state evidence). The six legacy boxes are not stranded — they are PRE-TRANSLATION, exactly the state the mechanism was built for, and they convert automatically on their next ./sb install / config generate, which arrives with the stable promoted from rc.11. So today's read slots cleanly into the ticket's own remaining-work definition (comment #12): the fleet's six pending translations are now enumerated by box with before-state evidence; per-box after-evidence is role-key-present + channel-key-absent in .env.config. CLOSURE PATH unchanged: all boxes show the role form → delete the translation case per its own removal marker → close. The one genuinely NEW item from the read is test's dead upgrade service (role=production set, no service running — note: test already carries the NEW form, so it translated or was created post-mechanism; its service absence is a separate defect, investigation dispatched).
---

author: operator (pinned by foreman)
created: 2026-08-27 19:45
---
TEST BOX DIAGNOSIS (2026-08-27, read-only): the upgrade service is NEVER-INSTALLED — not crashed, not disabled: `Unit statbus-upgrade@statbus_test.service could not be found`, enabled-state not-found, journalctl empty, no unit file at ~/.config/systemd/user/. The box is half-configured: .env.config carries UPGRADE_ROLE=production (correct intent — and already in the NEW key form) but the service-installation step never completed. CONSEQUENCE that makes this matter beyond one internal box: without an upgrade service, test can never receive the stable via channel-following — unlike the six legacy boxes whose services run and poll. REMEDY (not applied, read-only constraint): `./sb install` on the box — the product's own idempotent repair path; its state ladder covers exactly this (config present, service absent → step-table completes setup). Awaiting the King's word before any state-changing action on the box.
---

author: foreman
created: 2026-08-27 19:53
---
TEST LEG RESOLVED (2026-08-27 ~19:52Z, King-cleared, operator-executed): `./sb install` on the test slot completed all 16 steps — the never-installed upgrade unit now exists, is enabled and RUNNING, verified from the running service per this ticket's own acceptance rule: 'Upgrade service started (channel=stable, interval=6h0m0s)' (role=production deriving stable, correct). Upgrade list shows v2026.08.0-rc.10 installed via ./sb install. An earlier 'install truncated/incomplete' report was a capture artifact — corrected by the operator; the install itself never failed. Every box in the fleet now has a live, correctly-channeled upgrade service. Remaining for closure unchanged: the six legacy boxes' one-time translations (arrive with the stable), then the translation code's deletion.
---
<!-- COMMENTS:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
CLOSED on observed state, 2026-08-31: both closure observables met on every box. The fleet convergence run (King-driven, operator-executed, foreman-gated per slot) put v2026.08.0 on et, jo, ma, ug, ua, gh (demo had converged unaided the day before); on every box the one-time channel→role translation ran and was verified by read (UPGRADE_ROLE present, legacy UPGRADE_CHANNEL removed — the durable mechanism live fleet-wide), and the stale RC offers were superseded/purged by the new binary's own ledger maintenance. The July-era binaries that could never verify artifacts are gone from every serving slot (tcc exempt — retiring under STATBUS-321). The premise this ticket was born with — production boxes shown RCs as installable — is dead in both mechanism (the filter now runs everywhere) and fact (the offers are gone). Remaining per the ticket's own closure path: the translation case in cli/internal/config/upgrade_role.go can now be DELETED per its own removal marker (every box shows the role form) — that deletion is the one follow-on, riding the next candidate.
<!-- SECTION:FINAL_SUMMARY:END -->
