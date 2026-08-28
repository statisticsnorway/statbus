---
id: STATBUS-282
title: >-
  test-lock-host-death: the flock frees when the host tree dies while
  container-side pg_regress survives — the straggler mechanism, now
  twice-observed
status: Done
assignee:
  - '@engineer'
created_date: '2026-08-27 16:44'
updated_date: '2026-08-28 00:13'
labels:
  - testing
dependencies: []
priority: medium
type: bug
ordinal: 275000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Twice-observed mechanism (May's straggler that corrupted the King's 105 run; the engineer's harness-killed suite 2026-08-27 leaving pid 92456 walking the full list): the test-run flock releases when the HOST process tree dies, but the CONTAINER-side pg_regress does not inherit that fd and outlives it — so the lock reports free while a writer still walks the shared --outputdir. The next run would race it into NUL corruption; today only check_no_straggler_pg_regress (lock-acquisition-time) stands between.

The guard held both times it was consulted — the gap is that lock-freedom and writer-absence are different facts. Design question for the architect: should the lock's holder be (or include) the container-side process — e.g. the lock releases only when the db container confirms no pg_regress remains (fold the straggler check into release rather than only acquisition), or the runner wraps pg_regress so a host death tears down the container-side process group? Also the operational half: teammate harness timeouts have now killed a long suite mid-run — long test runs need an invocation that outlives session limits (detached tmux, as vm-bootstrap itself uses).

WHAT IS ACHIEVED: a dead host run cannot leave a live writer behind a free lock, and long suites survive their operator's session limits.
<!-- SECTION:DESCRIPTION:END -->

## Comments

<!-- COMMENTS:BEGIN -->
author: foreman
created: 2026-08-27 17:02
---
SECOND CONSEQUENCE of the same host-death gap, observed on the 2026-08-27 straggler (pid 92456): the wrapper died with the host session, so its cleanup never ran and SIX test_shared_* clone databases were left stranded (test_shared_27336/41027/45227/72674/83196/86286) — each a full clone of the migrated template. The engineer cleared them with the sanctioned ./dev.sh clean-test-databases before the 263 re-run. So the gap costs: (1) a stale pg_regress writer racing later runs' result files (the NUL-corruption class), AND (2) leaked clone databases accumulating disk. Both consequences trace to cleanup living in the host-side wrapper while the work lives in the container — whatever fix this ticket lands should move or mirror cleanup to where it survives host death.
---

author: foreman
created: 2026-08-27 17:14
---
CROSS-REFERENCE: the corruption MECHANISM verdict now lives in STATBUS-286 (offset-discontinuity, architect's superseding ruling 2026-08-27). This ticket's scope is unchanged — the host-death gap is one PRODUCER of stale writers/handles — but attribution of any NUL-corrupted result file goes through 286's frame (offset discontinuity; process count is a detail beneath the property), and the tripwire instrumentation (lsof + host-and-container process table + stat at fire time) is 286's deliverable.
---

author: architect
created: 2026-08-27 19:46
---
**RULING part 1 of 2: (a) and (b) are structurally dead. The postmaster becomes the lock.**

## The principle that decides it — and it is the same one 263 landed on tonight

> **What must survive a failure cannot live inside the thing that fails.**

The failure here **is the death of the host process tree**. So no host-side code can be the remedy — and that disposes of two of the three options without further argument:

- **(a) fold the check into lock RELEASE.** The release path is host-side. On SIGKILL nothing host-side runs; the flock frees because the *kernel* closes the fd, not because our code did. A release-time check runs in exactly the case that is already fine and is skipped in exactly the case that is broken.
- **(b) wrap pg_regress so host death tears down the container-side group.** Same defect — a host-side teardown handler is precisely what does not run when the host is killed. **And it fails a second time independently**: tearing down means signalling, which STATBUS-188 forbids.

Both options try to fix a failure domain from inside it.

## The ruling: **(d)** — the fact must live where the WRITER lives, and it already does

The writer is a Postgres client. **The postmaster already knows, exactly and continuously, which clients are alive.** That is `pg_stat_activity`, and it has every property this guard needs:

- it is **in the writer's own failure domain** — host death cannot make it lie;
- it is **released by the postmaster automatically** on client death — no cleanup code to fail to run;
- it requires **no signalling** — 188 is satisfied by construction, not by discipline;
- it observes a **connection**, not a process, so a dead pg_regress whose psql child still holds the DB is still visible.

**So the authority for "may I start a run" becomes a query for backends attached to `test_shared_*`** — not a host flock, and not `pgrep`.

**The property that makes this strictly better than the container-side `pgrep`:** the observation channel and the work channel become **the same channel**. Today we can fail to observe and still proceed (part 2). Under this design, if we cannot reach the database to ask, we cannot reach it to run the tests either. **Being blind and proceeding stops being reachable.**

Keep the flock if you like as a cheap host-side mutex, but it is **no longer the authority**: it may only ever produce a false BUSY, never a false FREE.

## The clone leak is the same fact, so it is the same fix

Comment #1 asks that cleanup move to where it survives host death. It does, for free:

- a `test_shared_*` database in `pg_database` with **zero** backends is an orphan → **`DROP DATABASE`**, which is the postmaster's own teardown, not a signal;
- one **with** backends is a live run → never touched, never dropped, never FORCEd.

`DROP ... (FORCE)` is banned here: it terminates backends, which is signalling by another name.

One mechanism now answers both questions the ticket opened, because **lock-freedom and writer-absence stop being different facts** — the guard observes the writer directly instead of a host-side proxy for it.
---

author: architect
created: 2026-08-27 19:46
---
**RULING part 2 of 2: a fail-open in the CURRENT guard, the PID hazard, the detached-run ruling, and a comment that is now contradicted by evidence.**

## MUST-FIX, and it may be the actual gap — the guard cannot tell "looked and saw nothing" from "could not look"

`dev.sh:519`:

```
_straggler=$(docker compose exec -T db pgrep -af 'pg_regress|HIDE_TABLEAM' 2>/dev/null) || return 0
```

The comment above it (`:516-517`) states the intent: *if the db service isn't running there is nothing to race with.* True — but `|| return 0` swallows **every** non-zero exit, and they mean opposite things:

- **pgrep exit 1** — looked, found nothing → genuinely clear;
- **`docker compose exec` failure** — daemon busy, container restarting, exec rejected → **never looked**, and the guard reports SAFE.

And `2>/dev/null` discards the one thing that would tell them apart. **A failure to observe is being treated as evidence of absence** — on macOS Docker Desktop, whose unresponsiveness is documented well enough in CLAUDE.md to have its own restart procedure.

The ticket says the guard held both times it was *consulted*. **This is how it could pass without consulting anything, and leave a log that looks identical to a real all-clear.**

```
docker compose ps --status running --format '{{.Service}}' | grep -qx db || return 0   # no container, no writer
_out=$(docker compose exec -T db pgrep -af 'pg_regress|HIDE_TABLEAM' 2>&1); _rc=$?
case $_rc in
  0) ;;                       # straggler -> BLOCK
  1) return 0 ;;              # pgrep looked, found nothing -> clear
  *) echo "REFUSING: could not observe the db container ($_rc): $_out" >&2; exit 1 ;;
esac
```

**Fix this even if the rest of the ruling is deferred** — it is small, it is independent, and it is the difference between a guard and the appearance of one.

## `test_shared_$$` — never derive ownership from the name

The clone is named for the **host** PID (`dev.sh:1083`). After host death that name identifies nobody, and **host PIDs are recycled** — a later run can compute a name that already exists, belonging to a straggler still using it. Under this ruling ownership comes from `pg_stat_activity`, never from the name. Keep the name if it is useful for humans; **never let any code branch on it.**

## The operational half: sanction the detached run, in `dev.sh`

**Yes — make it a documented `dev.sh` mechanism, not lore.** `dev.sh:476-484` already prescribes exactly this remedy in prose ("size the run's own timeout to the workload, or detach it"), and prose is what produced tonight's outcome: a pattern that worked for one engineer and is not reproducible by the next.

Two constraints on it:

1. **It must own its tmux socket explicitly** (`-L <name>`), never inherit the ambient one — the harness-must-not-leak-host-config rule. A default-socket assumption is wrong on this machine today.
2. **Name the consequence honestly:** sanctioning detached runs makes host-tree death **normal rather than exceptional**. That is an argument FOR the postmaster-side authority, not against detaching — but a detached mechanism shipped on top of a host-side guard would be shipping the failure mode as a feature. **Land the guard first, or land both together.**

## Interaction with 286 — this becomes a free experiment, but it does not settle it

If this fix structurally prevents a second **pg_regress**, then a recurrence of the corruption afterwards — with the guard *verified consulted* — is **evidence against 286's second-writer branch**. That complements the container-local-outputdir experiment already specified there.

**It narrows; it does not settle.** 286's discontinuity could involve a writer that is not a second pg_regress, and this ticket says nothing about those.

## And correct the comment at `dev.sh:496-499` when you are in the file

It asserts the two-writer mechanism yields *"a sparse NUL hole"*. **Tonight's `SEEK_HOLE` probe found NO holes in either corrupted artifact** — the zeros are materialised. That text is the anchor of the old 158-class verdict and it will keep re-teaching a mechanism the measurement does not support. Soften it to what is observed: a zero-filled gap, page-aligned start, arbitrary end, sparseness unproven.
---

author: foreman
created: 2026-08-27 19:53
---
THIRD INSTANCE of the operational half, tonight on a LIVE BOX (2026-08-27 ~19:52Z): the test slot's repair `./sb install` was run through a single held ssh session from the operator's harness; output truncated mid-[DDL]-quiesce (containers stopped, 'resume after Migrations succeeds' printed, then nothing) and the upgrade unit still absent afterwards — consistent with the harness session ending and killing the remote install mid-flight, exactly the host-death class this ticket's operational half names, now with a production-adjacent blast radius (a box left quiesced mid-install rather than a test artifact). Diagnosis dispatched before any re-run (is the process alive? flag holder? container states) and the re-run instruction is nohup-detached with short poll reads — never a held session for a long remote operation. Design consequence for the ruling already pinned here: the sanctioned-detached-invocation mechanism should cover REMOTE operator actions (ssh'd installs/upgrades), not only local suites — same failure, different host.
---

author: foreman
created: 2026-08-27 19:53
---
RETRACTION of comment #5's inference (verify-premises discipline): the test-slot install was NOT killed — the operator's corrected report shows it completed all 16 steps, the upgrade unit is installed and running, and the RUNNING service logs 'Upgrade service started (channel=stable, interval=6h0m0s)'. Only the operator's OUTPUT CAPTURE truncated at step 10; the remote process survived its ssh session ending. So tonight's count of session-death instances stays at TWO (the local suite kills), not three — and, worth noting for the design's threat model: a remote `./sb install` evidently survives its invoking session's death on its own (likely because install's own long-running children detach from the ssh tty), which is WEAK evidence, not a guarantee — the nohup-detached instruction for remote long operations stands as the safe default, but the claimed live-box instance of this failure class is withdrawn.
---

author: foreman
created: 2026-08-27 20:29
---
MUST-FIX LANDED at 4fdea9a2b (dev.sh only, 30/7, mechanic executing the architect's exact snippet; shellcheck delta identical, bash -n clean). The guard now distinguishes looked-and-clear from could-not-look: running-container pre-gate → clear; pgrep exit 1 → clear; any other exit → REFUSING loudly with the observation failure named, exit 1. PROVEN LIVE on all three arms, none from reading: (1) a real pg_sleep psql planted in the real db container → BLOCKED banner naming its pid, exit 1; (2) same container clean → return 0; (3) a PATH docker shim (real daemon untouched) passing the pre-gate but failing exec with exit 2 → the REFUSING line verbatim — demonstrating that the OLD form silently returned clear in exactly that scenario. The :496-499 comment no longer asserts a sparse hole the SEEK_HOLE probe disproved — softened to the observed geometry per 286. REMAINING in this ticket: the postmaster-becomes-the-lock build (pg_stat_activity authority + zero-backend orphan DROP + sanctioned detached-run mechanism with its own tmux socket, landing with-or-after the guard — the guard half is now in), engineer's queue after 267.
---

author: foreman
created: 2026-08-27 21:34
---
INCIDENT + FIX on the must-fix itself (2026-08-27 ~20:34-21:35Z): the landed guard KILLED CI. Under dev.sh's set -euo pipefail (line 9), the capture `_out=$(...); _rc=$?` dies on the assignment when pgrep exits 1 — the NORMAL clean-container case — so every fast-tests run at 4fdea9a2b aborted silently (exit 1, zero output, 0.3s after seed-fetch: the exact CI signature that triggered the investigation). Two lessons, both already in our book and both bitten anyway: (1) STATBUS-261's errexit-safe capture idiom (`_rc=0; _out=$(cmd) || _rc=$?`) applies to EVERY capture in an errexit script — the architect's prescribed snippet carried the landmine and neither his review nor the mechanic's build caught it; (2) A PROOF HARNESS MUST REPLICATE THE CALLER'S SHELL MODE — the three-arm proof ran the extracted function outside set -e, so arm 2 passed in the harness and killed the caller. FIX LANDED at 443a65629 (foreman, urgent: master fast-tests red also blocks the next cut's 288 oracle): errexit-safe idiom + the incident recorded at the line; ALL THREE ARMS RE-PROVEN UNDER set -e against the real container (clean → continues; planted pg_sleep straggler → BLOCKED by pid, exit 1; shim-failed exec → REFUSING verbatim, exit 1); planted process waited out, never signalled; container verified clean after. Assignee moved to engineer for the remaining postmaster-lock build.
---

author: foreman
created: 2026-08-27 22:24
---
STRUCTURAL HALF LANDED at 51f268b0b (dev.sh, +223) after the architect's LAND on the re-frozen unit — verified in the bytes, and STRONGER than his prescription twice: the guard strips whitespace before the emptiness test (his own one-liner would have false-BUSYed on psql's trailing newline — his words), and the real-entry arm additionally proves the refusal PRECEDES the work (no test runs), pinned at dev.sh:885-889 rather than on the function in isolation. TWO LESSONS RECORDED AS COMPLEMENTARY, per his explicit instruction — neither may displace the other: (1) WHY THE BAD LINE EXISTED — two concurrent shell RED harnesses, the second restoring a snapshot taken while the first held the mutation: two writers, one artifact, no error from either side — the ticket's own subject reproduced in the tooling built to prove the ticket, which is evidence FOR the premise; (2) WHY TEN ARMS PASSED OVER IT — the original proof contained NO refusal arm; the unit's central property was unpinned, and a correct-looking table can never catch what it does not test. Lesson (2) is the one that generalises to every future guard. HARDENING CONVERGENCE noted by the architect: the harness fix (exclusive flock + descend-marker distinguishing beside from under) is the same shape as the ticket's own fix — a mutex plus a liveness-and-provenance distinction — and tooling and subject converging on one answer is usually the sign it is right. WITH THIS THE TICKET'S GOAL IS MET: the authority lives where the writer lives (a dead host cannot leave a live writer behind a free lock — the lock IS the writer's presence), orphan clones are swept by the postmaster's own teardown, and long suites have a sanctioned session-surviving invocation. Rides the next candidate.
---

author: foreman
created: 2026-08-28 00:13
---
POST-CLOSURE FIX at c41a8fc1e (+40, dev.sh): the landed authority blocked CI itself — pg_regress on the runner died on 'REFUSING: could not ask the postmaster... service db is not running', because the ONE state no proof arm had pinned was db-not-running, which is a CLEAR BY CONSTRUCTION (a nonexistent postmaster has no backends), not an observation failure. Pre-gate added to both the authority and the orphan sweep (the sweep's reachability premise died with the authority's early return). DEVIATION RULED KEPT by the foreman on the ticket's own standing principle: the sibling guard's one-liner pre-gate shape reads a docker-command failure as clearance — the exact failure-to-observe-as-absence defect this ticket exists to prevent; the authority's pre-gate instead distinguishes docker-answered-no-db (clear) from docker-could-not-answer (fall through to the probe's loud refusal). Proven 14/14 with the discriminating pair: 6a clears via pre-gate WITH a live backend planted (short-circuit proven, not idleness), 6b shim-with-db-present still BLOCKS (an always-clear pre-gate would silently disable the authority — the zero-scope failure one level down, pinned this time). The harness surrendered its own defect en route: cleanup waited only the last planted pid, orphaning an earlier arm's backend into the next run's least-tolerant arm — every pid now tracked. THE PATTERN, third instance tonight and now unmistakable: the case that fires is the case no arm pinned — db-down for this guard, the refusal arm for the first version, set -e for the capture. Fourth-time rule for future guards: enumerate the WORLD-STATES the guard can meet (running/stopped/unreachable/absent), not just the answers it can receive.
---
<!-- COMMENTS:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
The host-death gap is closed on the side that survives host death. The authority for starting a test run is no longer a host-side flock (which the kernel frees when the process tree dies) but the postmaster itself — backends attached to test_shared_* databases, queried where the writer lives, so lock-freedom and writer-absence stop being different facts and a run that cannot observe cannot start. Orphaned clone databases are swept by plain DROP, protected two-layered (the sweep never asks about a live database, and PostgreSQL refuses even when asked — FORCE being the switch that disables that floor is why its ban is structural). Ownership never derives from the recycled pid-based name. Long suites gain a sanctioned detached runner that owns its tmux socket explicitly. The unit survived its own drama: its fail-open first version was produced by two concurrent RED harnesses corrupting the shared file (the ticket's own two-writer subject, reproduced in its tooling) and passed a seven-arm proof that lacked the refusal arm — both lessons recorded as complementary, the missing-central-pin one being the generalisable half. The guard's fail-open observation fix (earlier commit) plus this landing close the whole arc. Landed at 51f268b0b.
<!-- SECTION:FINAL_SUMMARY:END -->
