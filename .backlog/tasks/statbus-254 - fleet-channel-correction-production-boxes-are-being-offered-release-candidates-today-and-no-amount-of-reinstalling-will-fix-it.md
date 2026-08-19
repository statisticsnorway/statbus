---
id: STATBUS-254
title: >-
  fleet-channel-correction: production boxes are being offered release
  candidates today, and no amount of reinstalling will fix it
status: To Do
assignee: []
created_date: '2026-08-19 10:27'
updated_date: '2026-08-19 11:26'
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
<!-- COMMENTS:END -->
