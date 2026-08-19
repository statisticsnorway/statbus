---
id: STATBUS-254
title: >-
  fleet-channel-correction: production boxes are being offered release
  candidates today, and no amount of reinstalling will fix it
status: To Do
assignee: []
created_date: '2026-08-19 10:27'
updated_date: '2026-08-19 12:23'
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
Five statistical offices' production installations, plus demo, are currently set to receive release CANDIDATES rather than releases. That is the precise thing the release topology was designed to prevent, and it is live right now. Worse, it cannot be fixed by any normal operation: the setting is remembered forever and nothing recomputes it.

**THE EXPOSURE, plainly.** Ethiopia, Jordan, Morocco, Turkish Cypriotic Community and Uganda — real installations serving real statistical offices — are on the prerelease channel, as is demo. Their upgrade services will discover and offer release candidates, and the only reason they have not been installing them is that nobody has been pressing the button. Dev, which should be the box that takes candidates first, is on a third setting again (edge, tracking every master commit).

**WHY IT CANNOT SELF-CORRECT, and this is the part that matters most.** The channel is written once, at box creation, and preserved forever afterwards. `./sb config generate` fills in a value only when the key is ABSENT (cli/internal/dotenv/dotenv.go:223-225 — `Generate` returns the existing value and writes only on a miss). So every subsequent config generate, every reinstall, and every future change to what the correct default IS, all leave the original value untouched. **These boxes were configured before the current defaults existed** — the mode-aware default landed 2026-06-21 (commit 2393c028a) and the cloud slots predate it — and they have carried the old convention ever since.

This is the same defect family the release work has been closing all along: a value that persists because nobody re-derives it, with no check that it still means what it should. The channel is **remembered, not decided.**

**THE CORRECTION — the design question this entry exists to settle.** Our rule is that fixes ship as code and reach a box through its own install, never as hand-surgery over SSH. That rule and "change the setting on six live boxes" appear to conflict, and the way out is not to bend the rule but to stop storing a value nobody recomputes:

**RECOMMENDED: derive the channel instead of remembering it.** A box's channel should be a consequence of what the box IS, recomputed on every config generate, rather than a value inherited from the day it was created. Ordinary installations derive `stable`. A canary is an explicit, declared exception — which is what the topology already says a canary is: something configured deliberately, never arrived at by default.

Then the correction needs no special mechanism at all. It ships as code, and every box picks it up through the one operator action the product already has — `./sb install`. No SSH writes, no per-box surgery, nothing to remember to undo. It also permanently removes the failure mode rather than this instance of it: no future box can drift, and no future default change can fail to reach the fleet.

Note what this deliberately is NOT: a standing self-heal that quietly rewrites operator intent. Deriving a value is not repairing it — there is nothing to repair, because the value stops being independently settable. A box whose declared role and channel disagree should say so loudly rather than silently choosing.

**THE ALTERNATIVE, named so the choice is informed:** correct the six boxes now by running the product's own configuration command on each, and fix the mechanism afterwards. It is faster, and it is exactly the per-box manual mutation our rule exists to prevent — six boxes touched by hand, no record in code, and the same drift free to recur. Recommended only if the exposure is judged too urgent to wait for the mechanism, and it should then be followed by the derived-channel work regardless.

**SEQUENCING, which is not optional.** This correction must land BEFORE the deletion of the remaining per-slot deploy workflows for those five boxes. Those workflows are currently the only push path into those installations; removing them while the boxes are still on the wrong channel could leave a statistical office with no working route to receive anything at all.

Order within the work: correct the five NSO boxes and demo to `stable` first, since that is the live exposure. Dev moves to `prerelease` last — it is the mildest deviation, since edge at least tracks master, and it becomes moot once the release chain drives dev directly.

**WHAT IS ACHIEVED:** production installations stop being offered software that was never blessed, the fleet's settings become something the system computes rather than something it inherited, and the next time we change what a box should follow, the fleet actually follows.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 The live exposure is confirmed per box before and after: each box's channel is read from the box, never inferred from the default or from this ticket
- [x] #2 Five NSO installations and demo are on the stable channel; dev is on the channel its canary role requires
- [ ] #3 The correction reaches every box through code plus the box's own install — no per-box SSH mutation, unless the alternative is explicitly chosen and recorded here
- [ ] #4 The channel is derived from the box's role on every config generate, so a stale value cannot survive a reinstall and a future default change reaches the whole fleet
- [ ] #5 A box whose declared role and channel disagree reports it loudly rather than silently choosing either
- [ ] #6 This lands before the per-slot deploy workflows for et/jo/ma/tcc/ug are deleted — no box loses its only receive path while still misconfigured
- [ ] #7 The first-writer-wins behaviour is recorded where the next person would otherwise trust config generate to fix a setting
<!-- AC:END -->

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
<!-- COMMENTS:END -->
