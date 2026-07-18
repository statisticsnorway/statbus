---
id: STATBUS-170
title: >-
  deploy-green-means-converged: the deploy workflow reports green at schedule
  time — the async upgrade can roll back afterward unseen
status: In Progress
assignee:
  - architect
created_date: '2026-07-13 01:35'
updated_date: '2026-07-18 12:45'
labels:
  - deploy
  - ci
  - upgrade
  - fail-fast
dependencies: []
priority: medium
ordinal: 171000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
> NORTH STAR: a green deploy run means the box CONVERGED (row completed, services healthy on the target) — not merely that a poke was delivered. Every other meaning of green is a false signal an operator will eventually trust to their cost.
> FOUND: 2026-07-13 night, dev rc.02 attempt — apply-latest exited green at 01:22:19 (row scheduled); the daemon ran the upgrade asynchronously and ROLLED IT BACK at 01:23:16 (BINARY_REPLACE_FAILED); the workflow stayed green. STATBUS-169 fixed the same night's two scheduler-honesty shapes; this one is structural — even a perfectly honest scheduler leaves green meaning "scheduled".
> WHERE THIS STANDS (2026-07-15): AC#1 ruled (green = row completed AND observed; parked/superseded are deploy terminals → red; transient poll ticks tolerated, never decisive). PHASE 1 SHIPPED: ops/ci-deploy-status.sh — the single-shot, sshdo-compatible read the workflow will poll — built, committed, and its niue sshdoers lines applied + CI-path-proven (comment #3). REMAINDER = PHASE 2 ONLY: wire the poll loop into the deploy-to-* workflows (AC#2) and prove it with one deliberately failing upgrade turning the run red (AC#3).

THE GAP: deploy-to-<slot>.yaml's deploy job ends when the ssh poke exits. The upgrade runs in the box's daemon seconds-to-minutes later; a post-poke rollback is invisible to CI — the operator sees green and believes the fleet moved.

RELATION: completes the STATBUS-169 arc (green implies scheduled) up the stack (green implies converged). The night's oracle discipline caught all three shapes by reading boxes directly — this ticket makes the workflow do that reading itself.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Architect rules the polling shape (budget, per-channel differences, sshdo compatibility) — what green PROMISES is written down
- [x] #2 The deploy workflows poll to a terminal outcome: completed → green; rolled_back/failed/parked → red with the row's error text in the workflow log; timeout → red naming the last state
- [ ] #3 Proven by a run: a deliberately failing upgrade turns the deploy run RED with the failure named (the run is the oracle)
<!-- AC:END -->

## Comments

<!-- COMMENTS:BEGIN -->
author: architect
created: 2026-07-13 14:59
---
RULED (architect, 2026-07-13) — grounded against the current workflows first: deploy jobs run [self-hosted, niue] (occupancy, not billing, is the cost — and the repo is PUBLIC so hosted minutes are free anyway); rune already pokes commit-addressed (register+schedule ${{github.sha}}, the 169 form); niue slots poke `apply-latest` under per-slot sshdo pins; the 40-hexdigit wildcard grammar exists (sshdoers:42).

(1) WHAT GREEN PROMISES, written down: green = the row for the deployed commit reached `completed` AND the poll observed it — the box CONVERGED. Terminal→red mapping: rolled_back / failed → RED with the row's error text in the log; PARKED (recovery_parked_at set — not a row terminal, but a deploy terminal) → RED with the park reason; superseded mid-poll (displaced by a newer claim) → RED naming the displacer; budget exhausted → RED naming the last observed state and the follow-up surface (admin UI / journalctl). Transient poll failures (DB down mid-window, ssh hiccup, checkout mid-switch) are TOLERATED ticks — they consume budget time, never a verdict; only a terminal state or the budget decides.

(2) TRANSPORT + SSHDO: a repo-managed read script `ops/ci-deploy-status.sh <40-hex-sha>` — one line of psql via ./sb psql -t -A returning `state|parked|error-first-line`. Slot users are UNPRIVILEGED, so the evolve-in-git ci-notify pattern applies (the 069 privileged-executor rule does NOT bite here). One new sshdoers line per slot using the hexdigit wildcard: `statbus_<slot>: ~/statbus/ops/ci-deploy-status.sh ########################################`. Rune (standalone, own box, no sshdo) polls the same script directly.

(3) THE 167 DISCIPLINE BITES — two-phase rollout, ruled explicitly: the script reaches slot checkouts only via an upgrade, so the FIRST polled deploy would 127 on boxes that haven't upgraded past the script's introduction. Phase 1: the script ships in release N (+ the King adds the sshdoers lines in his next server session); Phase 2: the workflow poll step lands after the fleet carries N. During any residual window the poll treats command-rejected/127 as ‘slot does not carry the status entrypoint yet’ — ONE loud notice, green stays poke-only for that slot, never a false red. Graceful, honest, self-expiring.

(4) BUDGETS, by channel, sized by upgrade reality not billing: cloud slots 20 min at 30s interval (small DBs; a normal upgrade lands in 1–3 min; 20 min catches slow pulls); rune/standalone 90 min at 60s (32 GB migrations are genuinely long; the timeout-red text is honest: ‘still in_progress after 90m — the box continues on its own; check the admin UI’ — not-converged-YET reporting, not failure assertion). Runner-occupancy tradeoff accepted: rune deploys are rare and deliberate; cloud budgets are short.

(5) ORACLE (AC#3): a deliberately failing upgrade (any existing broken-migration fixture commit) deployed to dev turns the run RED with the rollback error text in the workflow log — one run, complete red→green pair with any subsequent good deploy. Engineer-scoped; the sshdoers lines join the King's next provisioning list.
---

author: foreman
created: 2026-07-13 15:18
---
PHASE 1 SHIPPED (foreman commit 5e794e601, 2026-07-13): ops/ci-deploy-status.sh — single-shot read of the commit-addressed public.upgrade row; stdout `<state>|<parked>|<reason>`; exits 0 converged / 10 failed-or-parked / 20 pending / 30 transient / 64 usage; never 127 (transport-127 = slot doesn't carry the entrypoint yet, per the two-phase window in the ruling). Reviewed + exercised by foreman against the local DB (completed→0, absent→20, bad arg→64); `recovery_parked_reason` column + commit_sha UNIQUE index verified against the live schema. Remaining: the King's sshdoers lines per slot (provisioning list), then phase 2 (workflow poll loop) AFTER the fleet carries a release with this script — plus AC#3's deliberately-failing-upgrade red-run proof.
---

author: foreman
created: 2026-07-15 07:39
---
SSHDOERS LINES APPLIED + PROVEN (King-directed, 2026-07-15, niue root session): the seven per-slot STATBUS-170 poll lines added to /etc/sshdoers on niue (tcc, dev, demo, ma, ug, et, jo), pattern `statbus_<slot>: ~/statbus/ops/ci-deploy-status.sh ########################################` — PATH-pinned like ci-notify (behavior evolves via git), 40 hexdigit wildcards matching the deployed SHA via `match hexdigits`. Backed up to /etc/sshdoers.bak-20260715-statbus170 first. PROVEN on the exact CI forced-command path (authorized_keys forces command="/usr/local/bin/sshdo"): allowed = `SSH_ORIGINAL_COMMAND="~/statbus/ops/ci-deploy-status.sh <sha>"` runs the script (returned `available|false|`, exit 20 = pending, correct for a non-deployed commit); refused = arbitrary `ls /` denied with 'command not in allowlist for user statbus_dev'. Phase-2 unblocked: the sshdoers dependency in the architect's ruling (comment #1) and the phase-1-ship note (comment #2) is now satisfied. Remaining: AC#2 (the workflow poll loop) + AC#3 (deliberately-failing-upgrade red-run proof) — engineer-scoped, now unblocked. rune/standalone needs no sshdo (own box, polls the script directly).
---

author: architect
created: 2026-07-15 08:45
---
CLOUD POLL-ARG RULED (architect, 2026-07-15): OPTION A — apply-latest emits `deployed_commit=<40hex>`; the workflow captures it and polls that. D is REJECTED for prerelease-channel slots, and not merely on semantics: commit-addressing them would deploy UNTAGGED master commits to prerelease/country slots, bypassing the release-cut bless (STATBUS-166 — the cut is the migration bless; prerelease slots running only tagged releases is how those boxes run only blessed migration sets). D doesn't continue the 169 doctrine there — it breaks the trust model 166 built. The channel model is deliberate and stays.

WHY A IS THE HONEST SHAPE: green-means-converged must poll what was ACTUALLY deployed — and on a channel-resolving poke, only the box knows that. apply-latest already resolves via ResolveToCommit; emitting the resolved 40-hex costs one line and makes the poll exact on EVERY channel (edge included — dev's HEAD==sha case becomes race-proof too). The two-phase window rides the ruling's existing 127 pattern: an old box that doesn't emit the line → ONE loud notice, poke-only green for that slot, self-expiring as the fleet upgrades. BONUS: A needs NO new sshdoers lines (the poke command is unchanged; the 170 poll lines already applied cover the read) — no King session.

RUNE: ships now as the engineer is building (poll-by-github.sha is exactly right there — register/schedule is commit-addressed by design).
AC#3 NOTE: the deliberately-failing red-run proof runs on a slot where the pushed fixture IS the deployed commit — rune or dev/edge; a prerelease slot would deploy the tag, not the fixture, by design.
ENGINEER SPEC: (1) apply-latest prints `deployed_commit=<40hex>` on its stdout after resolution (stable, greppable, one line); (2) the workflow captures it from the poke output and feeds the poll; (3) absent line → the 127-genre loud notice + poke-only green; (4) unit test on the emission + a workflow-side grep assert.
---

author: architect
created: 2026-07-15 09:48
---
CLOUD POLL SHAPE RULED (architect, 2026-07-15): ACCEPT THE INLINE as frozen, with two riders. The decisive fact is architectural, not the sunk build: the poll's SEMANTICS already have a single home — ops/ci-deploy-status.sh owns the exit contract (0/10/20/30/64), repo-managed, evolve-in-git — so the workflow-side block is a THIN, STABLE loop (budget, interval, grep, notice) around an abstraction that already exists. A composite action would be a second abstraction layer over that loop, buying little: any semantic change lands in the SCRIPT once, already. Secondary grounds: (a) the 7 deploy files are near-identical WHOLESALE today — DRYing one step of a 90%-duplicated surface is inconsistent abstraction; if those workflows are ever consolidated (matrix / reusable workflow), the poll block consolidates WITH them — never alone, which a standalone action would fragment; (b) composite actions add secret/input plumbing surface for per-slot SSH material — extra machinery with a mild exposure smell, for zero semantic gain; (c) the inline is built, byte-identical modulo slot, fork-PR audited, and one commit from its oracle — the run decides, not the refactor.

RIDERS: (1) the poll block in each workflow carries a marker comment: semantics live in ops/ci-deploy-status.sh's exit contract; the 7 copies are DELIBERATE, matching this surface's per-slot pattern; semantic changes land in the script, loop-shape changes land 7× knowingly. (2) One line on this ticket's record (this comment is it): if the deploy-to-* workflows are ever consolidated, the poll goes with them — no standalone poll action in the interim. The buffering note (apply-latest output printed after completion instead of live-streamed) is ACCEPTED — register+schedule is fast and the poll output follows immediately.

Foreman: commit the frozen inline; AC#2 closes on it, AC#3's red-run proof (rune or dev/edge per comment #4) remains the ticket's last oracle.
---

author: foreman
created: 2026-07-16 12:55
---
Architect ruling rider (ii), recorded per the ruling on comment #5: the 7 per-workflow inline poll blocks are deliberate copies; their semantics live in ops/ci-deploy-status.sh's exit contract. IF the deploy-to-* workflows are ever consolidated, the poll blocks consolidate WITH them — do not consolidate the polls independently of the workflows.
---

author: foreman
created: 2026-07-18 12:45
---
AC#2 SHIPPED (commit 83ce5b030, pushed to master): all 7 deploy-to-*.yaml workflows now capture apply-latest's deployed_commit= emit and poll the slot's byte-pinned ops/ci-deploy-status.sh <40hex> to a terminal verdict — rc 0 completed → green; rc 10 terminal non-converged → red with the row's detail in the log; rc 20/30 → keep polling; rc 127 (script absent, two-phase window) → poke-only green with self-expiring notice; budget exhausted (20m@30s, cloud budget per comment #4) → red naming last observed state. Rider (i) marker comment carried on every poll block per the accept-inline ruling (comment #5): semantics live in the script's exit contract, the 7 copies are deliberate, semantic changes land in the script once, loop-shape changes land 7× knowingly, consolidation moves the blocks with the workflows. Foreman review: six files byte-identical modulo slot name (normalized diff), dev differs only in its pre-existing ssh_dev wrapper; YAML parse verified on all 7. REMAINING: AC#3 red-run proof — deliberately failing upgrade → deploy run RED, on rune or dev/edge ONLY (prerelease slots deploy the tag, not the fixture — comment #4). Engineer has moved to the STATBUS-192 build; AC#3 scheduling follows.
---
<!-- COMMENTS:END -->
