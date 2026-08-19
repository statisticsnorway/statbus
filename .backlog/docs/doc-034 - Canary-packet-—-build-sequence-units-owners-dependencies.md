---
id: doc-034
title: 'Canary packet — build sequence, units, owners, dependencies'
type: specification
created_date: '2026-08-19 09:45'
tags:
  - release
  - plan
  - canary
---
Build plan for the approved canary packet: STATBUS-244, 245, 246, 247, 248, 249, 250.

The order is set by three constraints, in this priority: (1) never leave the fleet in a state where a candidate cannot be deployed to dev, (2) one owner per file — the shared tree forbids two agents in the same file, (3) foundations before consumers.

## Two findings that shape the plan

**A. Smoke is mostly wiring, not new work.** `test/install-recovery/scenarios/0-happy-install.sh` and `0-happy-upgrade.sh` both already exist, and `test-install.yaml` is already a single-scenario happy-install gate that already runs first. STATBUS-247's two smoke paths are therefore an existing scenario pair, not something to write.

**B. But the upgrade smoke must be its OWN workflow, not a subset dispatch — this is a ruling, not a preference.** `checkWorkflowAt` (cli/internal/release/workflow_check.go:152-157) queries runs by `head_sha` and returns the FIRST GREEN run it finds, not the most complete one. If a one-scenario smoke run and the full 28-scenario run both exist at the same commit under the same workflow identity, the gate can select the smoke run, find 27 required jobs missing, and fall through to the path-sensitivity walk — riding a PRIOR tag while a full green sits at that very commit. Giving the upgrade smoke its own workflow file keeps the `head_sha` query unambiguous. This is exactly why fresh-install smoke has never had this problem: `test-install.yaml` is already a separate workflow.

The alternative fix — make run selection prefer the run that satisfies completeness — is a larger change to a load-bearing gate and is NOT part of this packet. Separate identity is the cheap correct answer.

## Ordering constraint that must not be violated

STATBUS-244 deletes the nine master-to-X workflows. `master-to-dev` is the ONLY thing that currently deploys dev. STATBUS-247 replaces it with tag-to-dev. **Deleting master-to-dev before 247's tag-to-dev is live leaves no way to deploy dev at all**, during a period when the King is still cutting candidates and dev is supposed to gate the chain.

So 244 splits in two:
- **244a** — delete the eight non-dev master-to-X workflows, the demo and Norway deploy branches and their deploy-to-X workflows, and the doc sweep. Safe immediately: Norway is already on the prerelease channel with discovery already offering, so removing its push leaves it in its correct end state at once.
- **244b** — delete `master-to-dev`. Lands WITH or AFTER 247's tag-to-dev, never before.

`deploy-to-dev.yaml` is untouched throughout — it is 247's transport.

## Units

### Wave A — parallel, disjoint files

**A1 · STATBUS-249 — evidence marks + `./sb release covered`** — engineer
Foundational: 246 and 247's decision points both consume it. Mark written on scenario completion (scenario × code-state), mark lookup, the shared subcommand over the gate's existing library, and verdicts that name what they inherited.
Files: `cli/internal/release/`, `cli/cmd/release.go`, the harness scripts that write marks.
Depends on: nothing.

**A2 · STATBUS-244a — the sweep** — mechanic
Deletions plus documentation. Explicitly NOT `master-to-dev`, explicitly NOT `deploy-to-dev.yaml`.
Files: `.github/workflows/master-to-{demo,et,jo,ma,production,rune-no,tcc,ug}.yaml`, `deploy-to-demo.yaml`, `deploy-to-rune-no.yaml`, `AGENTS.md`, `doc/CLOUD.md`.
Depends on: nothing.
Trivial to fold in: the stale `cli/internal/upgrade/service.go:5305` comment claiming a "discovery loop's auto-schedule" that does not exist.

**A3 · Observation card CONTENT draft** — architect
The card 247 requires: what the operator should see at each step — suggestion text, decision prompt, progress messages, post-upgrade landing. My draft, the King's words. Goes to him in the same sitting as the 240 wording, which is still open.
Depends on: nothing. No code dependency at all.

### Wave B

**B1 · STATBUS-245 — canary gate rework** — engineer
Five named states, role-aware reading (awaiting-operator is Norway's resting state and dev's fault), per-role failure hints, never times out into a pass.
Files: `cli/cmd/release_canary.go` ONLY.
Depends on: 244a, so the hints are written once against the post-sweep reality.

**B2 · Upgrade smoke as its own workflow** — mechanic
New workflow running `0-happy-upgrade` on an ephemeral machine. Separate workflow identity per finding B.
Files: new `.github/workflows/test-upgrade.yaml`.
Depends on: nothing, but sequenced here to keep the orchestrator file single-owner in Wave C.

### Wave C — single owner, one file

**C1 · STATBUS-246 + 247 chain — decision points, superseded verdict, chain order, tag-to-dev, Norway offer** — engineer
Merged deliberately: both edit `release-fleet-orchestrator.yaml`, and the shared tree forbids two owners in one file. The decision points (246) and the chain order (247) are the same edit to the same joints.
Includes: decision point at every joint executed by the ARRIVING job; obsolete-check and covered-check; the third named verdict; chain order smoke → dev → fleets → Norway → promote; tag-to-dev deploy-branch write; Norway offer path with nothing automated calling schedule/apply-latest/install.
Files: `release-fleet-orchestrator.yaml`, `upgrade-arc-harness.yaml`, `install-recovery-harness.yaml`.
Depends on: A1 (marks), B2 (smoke workflow exists to order).

**C2 · STATBUS-244b — delete master-to-dev** — mechanic
Lands with or after C1. One deletion.

### Wave D

**D1 · STATBUS-248 — channel verification and disposition** — operator
Confirm each box is on the channel its ROLE requires: demo stable, Norway prerelease, dev prerelease as backstop. Demo is expected to need no change since stable is already the default for non-development boxes (`cli/internal/config/config.go:403-407`) — but it must be CONFIRMED on the box, not inferred.
Constraint: reads over SSH are fine; any change goes through the box's own config mechanism and the idempotent install, never an ad-hoc edit.

**D2 · STATBUS-250 — dev reset script** — mechanic
Wipe and reinstall dev at previous stable, dismiss the wrecking candidate so it is never re-offered. Interim fallback to previous RC until a stable exists in this line.
Depends on: C1, since it presupposes dev is the automatic canary.

## Landing coherence

Every wave boundary is a coherent state the King can cut a candidate against:
- After A: nothing has changed about how candidates reach boxes; marks exist and are being written.
- After B: the gate explains itself; smoke exists but is not yet ordered into the chain.
- After C: the full topology is live. This is the first cut that exercises the whole design.
- After D: the worst cases are scripted and the channels are confirmed.
