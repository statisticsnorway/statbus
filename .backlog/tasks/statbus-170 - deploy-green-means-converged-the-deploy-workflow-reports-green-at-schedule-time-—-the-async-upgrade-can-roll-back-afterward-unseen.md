---
id: STATBUS-170
title: >-
  deploy-green-means-converged: the deploy workflow reports green at schedule
  time — the async upgrade can roll back afterward unseen
status: In Progress
assignee:
  - architect
created_date: '2026-07-13 01:35'
updated_date: '2026-07-20 12:43'
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
> WHERE THIS STANDS (2026-07-20): AC#1 ruled and AC#2 SHIPPED — ops/ci-deploy-status.sh (the single-shot verdict read, exit contract 0/10/20/30/64) is committed, its seven niue sshdoers lines are applied and CI-path-proven, and all 7 deploy-to-* workflows + deploy-to-rune-no poll it to a terminal verdict (commit 83ce5b030). REMAINDER = the PROOF, King-ratified as fully automated (comment #10): AC#3 the arc-suite script-contract leg (failing-arc asserts exit 10/rolled_back and 0/completed on real rows) and AC#4 the dispatchable transport-proof workflow (broken-fixture arc VM + production-replicated sshdo transport + the poll-block bytes → red naming the failure). The one-time rune drill is RETIRED — nothing is ever deliberately broken on a fleet box. Architect builds both units hands-on (King's direct instruction); foreman commits and runs the oracles.

THE GAP: deploy-to-<slot>.yaml's deploy job ends when the ssh poke exits. The upgrade runs in the box's daemon seconds-to-minutes later; a post-poke rollback is invisible to CI — the operator sees green and believes the fleet moved.

RELATION: completes the STATBUS-169 arc (green implies scheduled) up the stack (green implies converged). The night's oracle discipline caught all three shapes by reading boxes directly — this ticket makes the workflow do that reading itself.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Architect rules the polling shape (budget, per-channel differences, sshdo compatibility) — what green PROMISES is written down
- [x] #2 The deploy workflows poll to a terminal outcome: completed → green; rolled_back/failed/parked → red with the row's error text in the workflow log; timeout → red naming the last state
- [ ] #3 The arc suite asserts ops/ci-deploy-status.sh's verdict contract on REAL end states: exit 10 + state=rolled_back on the failing arc's B row, exit 0 + state=completed on its C row — the script-contract leg, re-proven on every arc pass
- [ ] #4 A dispatchable proof workflow drives a broken-fixture arc VM and polls it through PRODUCTION-REPLICATED transport (probe user, sshdo/sshdoers from ops/niue/, hardened forced command, per-run ephemeral keypair — no standing secret) using the poll-block bytes (8th deliberate copy); the poll reports the failure red with the row's error text and a refused non-allowlisted command proves the gate — the workflow run is the oracle
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

author: architect
created: 2026-07-18 14:46
---
AC#3 PLAN RULING (architect, 2026-07-18) — all three questions ruled; the proposal is fully vetted for the King's go/no-go.

1. DEV/EDGE REJECTION: CONFIRMED — and I withdraw the dev/edge arm of my comment #4 ruling as a correction of my own error. Code-verified now: apply-latest on channel=edge fetches origin/master and deploys its HEAD (cli/cmd/upgrade.go:191-209) — the deploy-branch content is irrelevant on edge slots, so a fixture red-run there REQUIRES pushing the broken migration to master itself: a master-is-stable violation that propagates to every edge consumer and CI. rune is commit-addressed (deploy-to-rune-no.yaml:59: register + schedule ${{ github.sha }} from ops/standalone/deploy/rune-no), so the fixture stays entirely off master. RUNE ONLY.

2. FIXTURE + RED SHAPE: SOUND, conforms to the ruled shape. Affirmed: fixture = master 7f690fb22 + one broken migration (DO RAISE, the arc harness's _ut_write_failing_v genre; no-op down is CORRECT — rollback is volume-restore per STATBUS-039, migrate-down never runs); branch force-pushed to the deploy branch only; images via images.yaml --ref the fixture branch; expected chain backup → real 4-day delta applies → RAISE → autonomous rollback to 77fa16fb2 → row rolled_back carrying the exception text → poll exit 10 → workflow RED naming it. Review-time check: the timestamp-after-seed-target claim (image build survives, only the deploy fails). Note for the King's framing: this variant exercises rollback across a REAL delta — higher realism, longer Norway maintenance window.

3. CLEANUP: SOUND with three riders. (a) SEQUENCING — after the RED run, verify the box state matches expectation (rolled_back at 77fa16fb2, box serving) BEFORE firing the green half; never stack a deploy on an unexplained red state. (b) The GREEN half (clean master 7f690fb22 → same branch → real upgrade → completed → poll green) must be an EXPLAINED green (row completed keyed to 7f690fb22, box serving) before AC#3 checks; bonus accepted — it brings rune current. (c) EVIDENCE — reset the deploy branch to plain master and delete the fixture branch only AFTER both runs are adjudicated; weekly image GC is fine.

ALT FIXTURE (77fa16fb2 + poll workflow file + broken migration): TECHNICALLY SOUND — vetted, with its trade named so the King chooses between two vetted options. Mechanics hold: a descendant of rune's current registers as newer; images build from the branch; the migrate delta is ONLY the broken migration → near-instant RAISE → fast volume-restore → minimal window. Named trades: (i) it does NOT exercise rollback across a real delta — the smaller window is bought with weaker realism; (ii) off-master frankencommit lineage — after branch deletion the row references a commit existing nowhere; acceptable for a deliberate drill with evidence preserved in the row + logs; (iii) the green half still deploys master, so rune ends current either way. KING'S CHOICE: realism-with-longer-window (main) vs minimal-window-with-less-proof (ALT). Timing context the foreman may carry to him: this drill lands BEFORE Norway goes live on this box — the best possible moment to exercise production rollback machinery.

Pre-flight checks accepted as reported (rune idle, contract match, no deploy in flight, SSH secret intact). Nothing further from me until the run evidence lands.
---

author: architect
created: 2026-07-18 14:47
---
AC#3 CLEANUP ADDENDUM RULED (architect, 2026-07-18, supplements comment #8): the full-review cleanup section (C1-C6, no-separate-branch design) is APPROVED. The complete plan is now vetted end-to-end for the King's go/no-go.

VERIFIED SOUND: C1 keeping the rolled_back row is right — honest history, and no collision is POSSIBLE with the green half: rows are commit-addressed (169 doctrine), the red row keys to the fixture SHA, the green to master 7f690fb22; the green completion's supersede passes touch 'available' candidates and completed prereleases, never a terminal rolled_back row; the 159 atomic displace targets PARKED rows only, so it engages exactly and only in C4's contingency. C4's expected disposition is doctrine-correct: a mid-delta RAISE leaves observed-state Behind → rollback (145: Behind always rolls back; PARK is an at-target/unverifiable phenomenon) — rolled_back is the right expectation and park-instead is correctly treated as a STOP-and-report finding. C2's one-action design (force-push plain master = green trigger + pointer reset + fixture orphaning) is elegant and approved. C5/C6 satisfy my comment-#8 riders (a) and (b).

RIDER REMAP: comment #8's rider (c) — 'delete the fixture branch only after both runs are adjudicated' — is MOOT as written (no branch exists). Its intent transfers as two sequencing points: (i) RECORD the fixture commit's 40-hex SHA on this ticket before C2 fires — after the force-push the commit is orphaned and the row + workflow log + this ticket are its only durable references (the engineer's local clone retains the objects; do not rely on that alone); (ii) the RED run is adjudicated (rider a: rolled_back at 77fa16fb2, box serving, poll exit 10, workflow RED naming the RAISE) BEFORE C2 — C2 is both the green trigger and the orphaning act, so adjudication strictly precedes it. C3 weekly GC accepted; no explicit image delete needed.

Nothing further from me. The plan — venue (rune only), fixture + red shape, cleanup C1-C6 with the rider remap, and the vetted ALT — goes to the King.
---

author: architect
created: 2026-07-20 12:24
---
KING RATIFIED + PLAN REVISED (architect at the King's console, 2026-07-20) — AC#3 is REPLACED by the two automated ACs above; the rune drill is RETIRED. This comment supersedes the drill plan in comments #8/#9 (their venue analysis stands as history; their execution never runs).

THE KING'S CHALLENGE, and what it corrected: the drill proposal conflated 'the workflow only exists in CI' with 'the proof requires a fleet box'. It does not. What AC#3 must prove is poll-loop bytes + transport + status script against a genuinely failed upgrade — and an ARC VM can carry all of it: the arc suite already produces real rolled_back/completed rows via the real service pipeline, and the VM can be provisioned with the SAME transport as production because sshdo/sshdoers' canonical copies live in-repo (ops/niue/). Nothing is ever deliberately broken on a fleet box — dev cannot take a fixture at all (edge deploys origin/master HEAD, cli/cmd/upgrade.go:191-209), and rune no longer needs to.

THE TWO BUILD UNITS (architect builds hands-on per the King's direct instruction; foreman commits + runs oracles):
U1 — SCRIPT-CONTRACT ARC LEG: assertions.sh gains assert_deploy_status <vm> <40hex> <want_exit> <want_state> (runs ~/statbus/ops/ci-deploy-status.sh on the VM over the harness transport, asserts exit code + state field). failing-arc.sh calls it after phase B (10/rolled_back) and phase C (0/completed) — both verdict classes, one existing arc, no new VM cost.
U2 — TRANSPORT PROOF WORKFLOW: (a) a probe-provisioning helper installs sshdo root-owned from ops/niue/sshdo onto the arc VM, writes the sshdoers line for the probe user (the 40-hexdigit wildcard pattern), and installs the run's ephemeral pubkey under the HARDENED forced command (command=sshdo + no-agent-forwarding,no-port-forwarding,no-pty,no-X11-forwarding,no-user-rc — the 069-ruled prefix); (b) deploy-status-proof.yaml (workflow_dispatch, [self-hosted, niue], HCLOUD_TOKEN already a repo secret — verified) mints the keypair, drives install + broken-fixture deploy to rolled_back, then ITS OWN poll-block copy polls through the forced-command transport expecting exit 10 + the row's error text, plus one refused-command probe ('not in allowlist'); VM reaped in an always() step.
CADENCE: workflow_dispatch now; the foreman may add a schedule later — each run costs ~1 VM-hour.
RESIDUAL, named: the seven production workflows' red-branch lines are not executed by this proof — bounded by rider (i) (semantics live in the script, copies deliberately thin) and by every real deploy exercising the green path.
EVIDENCE RIDER carried over from the drill ruling where it still applies: the proof run must be an EXPLAINED red (state=rolled_back with the fixture's RAISE text) before the AC checks.
---

author: architect
created: 2026-07-20 12:38
---
BUILD DELIVERED (architect hands-on per the King's instruction, 2026-07-20) — both units coded, verified locally (bash -n + shellcheck clean incl. the deliberate SC2088 pair, workflow YAML parses), UNCOMMITTED in the working tree for the foreman's line review + commit. Five changes:

U1 (AC#3) — script-contract leg:
· test/install-recovery/lib/assertions.sh: new assert_deploy_status <vm> <sha> <want-exit> <want-state> — runs ops/ci-deploy-status.sh ON the VM, asserts exit code + the state field of the one-line verdict.
· test/install-recovery/arcs/failing-arc.sh: two calls — after phase B (10/rolled_back), after phase C (0/completed). Both verdict classes on real rows, every arc pass, zero new VM cost.

U2 (AC#4) — transport proof:
· test/install-recovery/lib/sshdo-probe.sh (new): setup_sshdo_probe <pubkey> — installs /usr/local/bin/sshdo root-owned from the canonical ops/niue/sshdo, writes /etc/sshdoers (match hexdigits + the 40-'#' status-read line for the statbus user — the faithful niue shape: the key lands on the service-owning user, the ALLOWLIST is the power), and appends the ephemeral pubkey under the hardened 069 forced-command prefix. STATBUS-021 discipline: the root-side script is written locally (quoted heredoc), scp'd, executed with the pubkey as an argument — no shell touches the payload in transit.
· test/install-recovery/arcs/deploy-status-proof-arc.sh (new): mints the per-run ed25519 keypair → installs the probe → GATE PROOFS pre-drive (refused: 'ls /' must deny with 'not in allowlist'; allowed: status read exits 20/absent — the niue provisioning proof shape) → drives B to rolled_back via the real daemon (arc_to, shared failing lineage) → THE POLL: the 8th deliberate poll-block copy (rider-i marker carried) through the ephemeral-key sshdo transport, INVERTED (exit 10 = PASS, exit 0 = FAIL, 127 = hard FAIL since the two-phase window can't apply on an arc VM) → asserts the EXPLAINED red (state=rolled_back + the fixture's RAISE text in the reason — the evidence rider) → assert_health_passes (the box itself recovered). Failure trap dumps row + journal + sshdo state incl. the sshdo auth log.
· .github/workflows/upgrade-arc-harness.yaml: one line — deploy-status-proof joins the failing-lineage case. The arc self-registers in the matrix (arcs/*-arc.sh glob), so the DISPATCHABLE proof run is: gh workflow run upgrade-arc-harness.yaml -f scenarios="deploy-status-proof" — and the full-suite run carries it recurringly.

HOSTING NOTE (one deliberate refinement vs the ratified wording, flagged for the King's visibility): the poll-block copy lives in the ARC SCRIPT inside the existing dispatchable harness, not in a separate workflow YAML — same bytes, same transport, same verdict, but zero duplication of the harness's construct/image-wait/cleanup machinery, plus the proof runs with every full-suite pass instead of only on dedicated dispatches. The mechanics the King ratified (arc VM, sshdo replica, ephemeral key, poll bytes, refused-command gate, no fleet box ever) are all intact.

ORACLES (foreman): (1) commit after line review; (2) one harness dispatch with scenarios="failing deploy-status-proof" proves BOTH units — AC#3 checks on failing's green (its two new asserts), AC#4 on deploy-status-proof's green (explained red observed through the gate). Local run works too (HCLOUD_TOKEN in .env.credentials). The run is the oracle.
---

author: architect
created: 2026-07-20 12:43
---
AMENDMENT after foreman line review (architect, 2026-07-20): confirmed bug in my sshdo-probe.sh, owned and fixed — ssh flattens argv into one remote-shell-parsed string, so the three-word pubkey re-split and arrived as $1='ssh-ed25519' with the key material dropped; comment #11's 'pubkey as an ARGUMENT — no shell touches the payload' claim was wrong at exactly that hop (the foreman verified the flattening against a live sshd). RULED (a): STDIN delivery — the setup script reads pubkey="$(cat)", the invocation feeds it via herestring (bash reads the script from the FILE so stdin stays free), making the STATBUS-021 claim literally true — PLUS a remote fail-fast validation (pubkey must match 'ssh-* <material>') that catches this truncation class at provision time instead of as an opaque transport failure three steps later. Locally verified: 3 fields / 99 chars preserved through the stdin path; bash -n + shellcheck clean. Header comment updated to name the argv-flattening hazard. Ready for the foreman's delta re-review of the changed lines → commit all five → the single harness oracle run (scenarios="failing deploy-status-proof").
---
<!-- COMMENTS:END -->
