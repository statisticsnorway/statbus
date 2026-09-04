---
id: STATBUS-248
title: >-
  retire-dead-deploy-transport: delete the writer-less deploy workflows and
  branches — channels stay as surveyed, cloud.sh is the rollout path
status: To Do
assignee: []
created_date: '2026-08-19 07:27'
updated_date: '2026-09-04 15:08'
labels:
  - release
  - ops
  - upgrade
dependencies: []
references:
  - .github/workflows/master-to-production.yaml
  - .github/workflows/production-to-all.yaml
  - cli/internal/upgrade/service.go
  - doc/CLOUD.md
priority: high
type: enhancement
ordinal: 241000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
KING'S RULING 2026-09-02, on surveyed facts (running-service reads, all 10 boxes, no drift): the CURRENT topology stays. dev=prerelease (explicit), Norway/rune=prerelease (the human canary posture), demo + et/jo/ma/mw/ug/ua/gh=stable (mode-derived default). No channel writes. He may later move demo to prerelease to demonstrate features early — a one-line .env.config edit + ./sb install, his call, no ticket needed.

Rollout is operator-driven via ./cloud.sh (status/install/upgrade/notify — candidate-addressed CLI), plus each box's own channel offers. GitHub deploy branches and their listener workflows have no writer and no user anymore (the manually runnable master-to-X workflows were retired in STATBUS-244; nothing writes the deploy branches since).

RemAINING WORK (the whole ticket): delete the dead transport.
1. Delete .github/workflows/deploy-to-{demo,dev,et,jo,ma,no,production,tcc,ug}.yaml and any master-to-*/production-to-* remnants (verify the orchestrator's deploy-to-dev DISPATCH path first — deploy-to-dev.yaml is still dispatched by release-fleet-orchestrator.yaml for the automatic dev canary and MUST STAY; delete only the ones with no dispatcher: grep the workflows for uses/dispatches before deleting).
2. Delete the deploy branches: ops/cloud/deploy/{demo,dev,et,jo,ma,no,production,tcc,ug} and ops/standalone/deploy/rune-no — EXCEPT any branch a surviving workflow still reads (deploy-to-dev's deprecated branch-push fallback: if deploy-to-dev.yaml stays, decide whether its fallback trigger goes too, then its branch).
3. Sweep doc/CLOUD.md and ops/ references to the deleted paths.

Acceptance: every deleted workflow had no dispatcher/writer (named check per file); the dev canary chain still works (next rc's orchestrator dispatches deploy-to-dev green); no ops/cloud/deploy/* or ops/standalone/deploy/* branches remain except those a surviving workflow reads; fleet channels re-verified unchanged after the deletions (they are config, not workflow, but verify anyway); doc/CLOUD.md carries the cloud.sh + channel-offers rollout story.
<!-- SECTION:DESCRIPTION:END -->

## Comments

<!-- COMMENTS:BEGIN -->
author: architect
created: 2026-08-19 07:37
---
SCOPE CARVE-OUT after the King's ruling 4 (three-role canary topology, STATBUS-247). This entry says "production slots follow the stable channel". That phrase now needs a boundary drawn on it, because one box is in both categories.

NORWAY (rune-no) IS BOTH. It is a real production deployment for a statistical office, and under ruling 4 it is also one of the two human-fidelity canaries — offered each candidate, installed by a person. So it must NOT be moved to the stable channel by this entry. It stays on the prerelease channel with a human performing the install, and STATBUS-247 governs it.

THIS IS NOT A NEW EXPOSURE, which I checked rather than assumed: doc/CLOUD.md:769 already authors standalone boxes with UPGRADE_CHANNEL=prerelease, so Norway runs release candidates today. Ruling 4 changes who presses the button there, not what channel it drinks from.

WHY IT MATTERS THAT THIS IS WRITTEN DOWN: an implementer reading "set the production slots to stable" and working from the deployment table would sweep Norway in, and the change would look tidy and correct. It would silently delete half the human-fidelity canary coverage, and nothing would fail — the gate would simply stop having a candidate to find, and the release process would get quieter rather than louder. That is the zero-scope-green shape (doc-033) arriving through a configuration change instead of a check.

SO THE SCOPE OF THIS ENTRY IS: production slots that are NOT canaries. Concretely, dev, demo and no are governed by STATBUS-247 and are out of scope here; everything else that is a live installation is in. AC#2's verification should therefore assert the channel each box is SUPPOSED to be on per its role, not that every box is on stable — a box on the wrong channel for its role is the failure this entry is meant to prevent, in either direction.
---

author: architect
created: 2026-08-19 07:39
---
SCOPE RESTATED under the King's final topology — this supersedes the carve-out in comment #1, which was written when demo was still a canary.

IN SCOPE for this entry (ordinary installations that follow releases on their own): **demo**, plus the production slots. Demo moved here by the King's ruling — dev already answers the does-it-install question, so a second automatic canary would only repeat it. Demo is now a normal box, and its promotion-day behaviour is this entry's question, not STATBUS-247's.

OUT OF SCOPE: **dev**, driven by the release chain; and **Norway**, the single human canary, which stays on the prerelease channel with a person performing each promotion-bound install against an observation card. Both are governed by STATBUS-247.

THE NORWAY WARNING FROM COMMENT #1 STANDS AND IS NOW THE ONLY ONE. Norway is both a real production installation and the human canary, so an implementer reading "set the production slots to stable" and working from the deployment table would sweep it in. That change would look tidy and correct, and nothing would fail — the gate would simply stop finding a candidate to wait on, and the release process would get QUIETER rather than louder. It would delete the entire human-canary role in one config edit. This is the zero-scope-green shape (doc-033) arriving through configuration instead of through a check, which is why it is written down twice.

AC#2 SHOULD THEREFORE ASSERT ROLE-CORRECT CHANNELS, not universal stable: each box on the channel its role requires, with a wrong channel failing in EITHER direction. A box quietly on stable when its role needs prerelease is exactly as broken as the reverse, and considerably harder to notice.
---

author: foreman
created: 2026-08-19 09:43
---
KING APPROVED 2026-08-19 (dialogue presentation, sixth and final of the sitting) — THE FULL PACKET IS NOW APPROVED: 244 (with the barring-248 reservation hereby lifted — AC#8's master-to-production/production-to-all removals unblocked), 245, 246, 247, 248, plus 249 and 250 approved earlier in the sitting. One consideration the King voiced and left with the foreman's input standing: demo's channel — stable (as ruled here) vs prerelease (the historical judge-before-release posture). Foreman's input, delivered: the judge-early need is now served by dev (every candidate, automatically — the historical reason for prerelease cloud slots predates that); demo's audience is outsiders who should see the released product; and the "choice to upgrade" instinct is honored natively — a deliberate one-off evaluation of a candidate on demo remains available via ./sb upgrade schedule <tag>, an explicit act rather than a standing posture. Demo stays on stable per this entry unless the King flips it — a one-line change inside this build if so.
---

author: foreman
created: 2026-08-19 09:52
---
KING'S AMENDMENT 2026-08-19 (post-approval, in confirmation dialogue) — supersedes AC#6's scope: the COUNTRY SAMPLE INSTALLATIONS (et, jo, ma, tcc, ug — every slot that is not dev/demo/no) are OPT-IN, not auto-converging: they sit on the stable channel, are OFFERED each promoted release, and a HUMAN clicks and performs the regular upgrade. Only DEMO auto-converges on stable. His full confirmed topology: dev = prerelease channel (backstop; actually chain-pushed), Norway = prerelease + human (the canary, excluded from any sweep), demo = stable + AUTO-APPLY (the one new behavior to build, scoped to demo alone — today's service only offers, never schedules, which is measured), country samples = stable + human opt-in (exactly today's offer-and-wait behavior — zero build), force-override = the existing candidate-addressed command (ssh <slot> ./sb upgrade schedule <version>), documented as THE deliberate override. Note the elegance the amendment buys: the country slots now behave exactly like customer boxes — customers ARE opt-in humans — so customer fidelity improves while the build SHRINKS (auto-apply for one box instead of many). Builder: amend AC#6 accordingly at build time; the channel-verification AC#3 gains a third role-state (stable+auto vs stable+opt-in vs prerelease+human).
---

author: architect
created: 2026-08-19 11:44
---
DEMO AUTO-APPLY TRIGGER — design, per the King's reuse ruling.

## THE CHOICE: a scheduled workflow, not a change to the service

Two shapes were available and they are not close.

**The box's own service tick** would mean teaching the upgrade service to auto-APPLY, not merely offer. That is a behaviour change in the product every statistical office installs — either for everyone, or behind a new setting that then needs its own ruling, its own default, and its own drift story (we have just spent a day on what one un-recomputed setting costs). Disproportionate for one demonstration box, and it would put a standing auto-install path into a product whose entire topology we just spent this campaign making deliberate.

**A scheduled workflow that runs the existing command** changes no product code at all. It is external, visible in one file, revocable by deleting that file, and touches nothing a customer installs. It is also literally what the King described: *the cloud tool already covers it, we just trigger the same thing.*

**Design: a scheduled GitHub Actions workflow that SSHes to `statbus_demo` and runs `./sb upgrade apply-latest`.** The access path already exists and is already allowlisted for exactly this command — `ops/niue/sshdoers` permits it for that user — so this adds no new privilege and no new credential. It rides a door that was already built and approved.

## WHY IT IS CORRECT NOW AND WOULD NOT HAVE BEEN LAST WEEK

`apply-latest` resolves the latest version **on the box's own channel** (cli/cmd/upgrade.go:210-232). Demo is now on `stable` (STATBUS-254, verified from the running service), so the command resolves the latest STABLE release. Before the fleet correction the same trigger would have installed release CANDIDATES on demo automatically — the exposure 248 exists to prevent, delivered on a schedule. **Note the ordering dependency in the entry**: this trigger is safe only because the channel correction preceded it, and it must never be built on a box whose channel has not been verified from the running service.

## THE TENSION WITH THIS ENTRY'S OWN RULE, named rather than glossed

248 says demo *follows releases on its own* and nothing pushes to it. A cron trigger is something external causing an install, which looks like a contradiction. It is not, and the distinction is the same one that let STATBUS-244 and 247 coexist:

**The trigger supplies the TIMING. The box still chooses the TARGET.** `apply-latest` resolves the version locally, from the channel the box declares. Nothing outside the box names a version, a commit or a branch — which is exactly what 244 forbids. Remove the workflow and demo is still correct, just slower. That is the test for whether a trigger is legitimate: **if deleting it would leave the box wrong rather than merely late, it was a push.**

## CADENCE AND FAILURE

Daily is right — demo exists to show what a customer would install, and a day's latency after a promotion is invisible to that purpose while keeping the log quiet enough that a failure stands out. `workflow_dispatch` alongside the schedule so it can be run on demand without waiting.

A failed run must be **loud and must not retry silently**: demo failing to take a promoted stable release is a real signal about the release, not a demo problem, and it is the only automatic full install-and-converge we get on the stable channel. Swallowing it would waste the one place that signal appears.

## WHAT THIS IS NOT

It is not a canary and must not be described as one anywhere. It gates nothing, no promotion waits on it, and its failure blocks no release. It is a demonstration box kept current by the same command an operator would type.
---

author: foreman
created: 2026-08-31 19:42
---
KING'S SUPERSEDING RULING (2026-08-31 evening): ALL cloud slots run PRERELEASE — demo INCLUDED. This supersedes this ticket's demo=stable ruling and comment #4's topology on that point. His words across the day: 'all the cloud channels were meant to be pre-release so we can test them and show things before others' … 'let's run all of the cloud in pre-release, yes' (given after the foreman presented the 08-19 demo=stable reasoning explicitly — a deliberate reversal, not an oversight). Consequence on record: demo's daily auto-apply workflow resolves on the box's channel, so demo will auto-install release CANDIDATES daily — under the old frame an exposure, under this ruling the intent (an auto-updating candidate showcase). Country slots stay human-opt-in — their offers are now rc offers. Norway unchanged (prerelease + human). The channel writes ship in the post-307-release transition per the pinned runbook (307 comment #11): operator writes, foreman-gated, same session as each box taking the new code.
---

created: 2026-09-02 10:27
---
foreman (2026-09-02): KING'S FINAL RULING supersedes comment #6's all-prerelease direction and everything before it. On the surveyed running-service facts (all 10 boxes, 2026-09-02): the topology STAYS AS IT IS — dev=prerelease, Norway=prerelease, demo+country slots=stable. No channel writes. He rolls the fleet forward himself via ./cloud.sh upgrade. He may later flip demo to prerelease (demonstrate features early) — his one-line call, no process. The ticket is now solely the dead-transport deletion; the description is authoritative and the older comments are history.
---

created: 2026-09-02 10:39
---
foreman (2026-09-02, later same morning): KING AMENDS the topology — demo moves to PRERELEASE. Rationale: with dev green on rc.02 but Norway (large, standalone) refusing it, he wants a manual test point for both a SMALL installation (demo) and a LARGE one (Norway) on the candidate channel. Target topology: dev + demo + rune=prerelease; et/jo/ma/mw/ug/ua/gh=stable. The demo channel write is his (or foreman-gated on his word): edit demo's .env.config UPGRADE_CHANNEL=prerelease + ./sb install — timing his call, sensibly after the Norway RCA verdict and on a binary carrying the current sweep fixes.
---
---
author: foreman
created: 2026-09-04 11:17
---
WAVE D1 SATISFIED (the King's ruling, 2026-09-04): demo, on the stable channel, received v2026.09.0 through its own upgrade service's periodic check (scheduled 12:58:22, completed 12:59:33 local, observed by the King in the admin UI) with no deploy-branch involvement. One box exercising the code covers the mechanism for every box running the same code — et/jo/ma/ug need no individual confirmation. The deletion guard is met.
Execution notes agreed: deploy-to-dev.yaml STAYS (dispatched by the orchestrator; ran green three times today). Its deprecated branch-push fallback trigger goes too, and then ops/cloud/deploy/dev with it — the orchestrator dispatch is the only real path. Per-file no-dispatcher check before each deletion, doc/CLOUD.md sweep, read-only channel re-verification across the fleet afterward. Terminology: say "manually runnable workflows", not "buttons".
---

author: foreman
created: 2026-09-04 16:33
---
REMOTE-BRANCH DELETION IS BLOCKED on a newly reproduced live-box hazard. `configureDeployFetch` in `cli/cmd/install.go` appended an explicit slot refspec such as `+refs/heads/ops/cloud/deploy/dev:refs/remotes/origin/ops/cloud/deploy/dev`. If that remote branch is deleted while the line remains, every form of `git fetch origin` fails with exit 128 (`fatal: couldn't find remote ref ...`), which wedges release discovery.

Required order, now part of STATBUS-248:
1. Land the product fix: delete the deploy-branch refspec writer. `upgrade.CanonicalRefspecs` remains the sole authority, and `NormalizeRefspecs` must leave exactly its two canonical lines. Add regression coverage proving no `ops/cloud/deploy` refspec is written and stale deploy refspecs are normalized away.
2. Survey every cloud box read-only. After the fix is available on a box, repair every noncanonical configuration through the product-owned path (`./sb install`, which calls `NormalizeRefspecs`) unless the foreman explicitly approves a targeted alternative. Verify each repaired box with `git config --get-all remote.origin.fetch`, expecting exactly the two canonical lines.
3. Norway/rune remains off limits to this implementer. The foreman handles its survey and repair with the King.
4. Only after every box is verified canonical may the already inventoried remote deploy branches be deleted. Re-list and re-check immediately before deletion; no earlier approval carries across this prerequisite.
---
---
author: foreman
created: 2026-09-04 15:08
---
ROOT CAUSE FOUND MID-EXECUTION, and it is bigger than "dead transport". The installer ITSELF wrote a per-slot git fetch refspec into every box that had a DEPLOYMENT_SLOT_CODE: configureDeployFetch was called from runCloneRepo AND runGenerateEnv, both ordinary steps of `./sb install`, gated only on the slot code being set and the branch existing on origin. So this is installer behaviour, not cloud-only residue — rune/NORWAY carries `+refs/heads/ops/cloud/deploy/no` too (verified read-only 2026-09-04 15:00; its fetch is exit 0 TODAY only because the branch still exists).

WHY IT BLOCKS DELETION: release discovery runs `git fetch --tags --prune-tags`, which consults every configured refspec. A refspec naming a deleted branch makes that fetch exit 128 (`fatal: couldn't find remote ref`), so the box would silently stop receiving upgrades — verified by Luna against the product's real fetch commands, tmp/luna-refspec-verification.md, after the foreman's generic reproduction was challenged by the King and re-tested faithfully. The service tick does NOT call NormalizeRefspecs first, so boxes do not self-heal by waiting.

KING'S RULINGS (2026-09-04): (a) NO new toolchain verb — this is a one-time manual cleanup of our own residue, not a product feature; (b) manual repair authorized on all niue cloud boxes AND rune/Norway; (c) no other NSO installation has a deploy branch, so there is no wider exposure.

EXECUTION ORDER, now part of this ticket: (1) code fix — configureDeployFetch removed, both call sites normalize only, regression tests forbid its return (d689a94d7, 186a96d73); (2) manual per-box repair of the DEPLOY LINE ONLY (boxes noncanonical for other historical reasons — mw tag-only, ua/gh duplicate db-seed — are left alone and reported); (3) verify each box: canonical two lines + `git fetch --tags --prune-tags --dry-run` exit 0 + service healthy; (4) ONLY THEN delete the 8 remote branches (all tips verified ancestors of origin/master). Workflow deletions, deploy-to-dev fallback removal and the doc sweep are already done and are independent of the branch deletion.
---
<!-- COMMENTS:END -->
