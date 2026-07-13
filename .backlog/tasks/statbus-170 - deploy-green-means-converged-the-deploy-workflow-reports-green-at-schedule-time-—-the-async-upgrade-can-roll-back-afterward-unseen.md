---
id: STATBUS-170
title: >-
  deploy-green-means-converged: the deploy workflow reports green at schedule
  time — the async upgrade can roll back afterward unseen
status: In Progress
assignee:
  - architect
created_date: '2026-07-13 01:35'
updated_date: '2026-07-13 14:59'
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
> FOUND: 2026-07-13 night, dev rc.02 attempt — apply-latest exited green at 01:22:19 (row scheduled); the daemon claimed and ran the upgrade asynchronously and ROLLED IT BACK at 01:23:16 (BINARY_REPLACE_FAILED); the workflow stayed green. Two other same-night shapes (Norway's UPDATE-0 and swallowed-constraint pokes) were fixed by STATBUS-169, but this one is structural: even a perfectly honest scheduler leaves green meaning "scheduled".
> COMPLEXITY: small workflow change + architect design ruling (what green promises, how long to poll, what terminal states map to red).

THE GAP: deploy-to-<slot>.yaml's deploy job ends when the ssh poke exits. The upgrade itself runs in the box's daemon, seconds-to-minutes later. A post-poke rollback (like tonight's) is invisible to CI — the operator sees green and believes the fleet moved.

SHAPE (architect to rule): after the poke, the workflow polls the box's upgrade row (read-only ssh, the row is commit-addressed) until a terminal state or a bounded timeout: completed → green; rolled_back/failed/parked → RED with the row's error text surfaced in the workflow log; timeout → red naming the last observed state. Design points: poll budget vs GitHub Actions billing; whether the edge slots (fast) and release slots (slower) need different budgets; the read command must be sshdo-compatible on niue slots.

RELATION: completes the STATBUS-169 arc (green implies scheduled) up the stack (green implies converged). The night's oracle discipline caught all three shapes by reading boxes directly — this ticket makes the workflow do that reading itself.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Architect rules the polling shape (budget, per-channel differences, sshdo compatibility) — what green PROMISES is written down
- [ ] #2 The deploy workflows poll to a terminal outcome: completed → green; rolled_back/failed/parked → red with the row's error text in the workflow log; timeout → red naming the last state
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
<!-- COMMENTS:END -->
