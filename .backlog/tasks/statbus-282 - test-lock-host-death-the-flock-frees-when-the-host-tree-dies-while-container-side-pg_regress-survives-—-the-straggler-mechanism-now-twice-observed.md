---
id: STATBUS-282
title: >-
  test-lock-host-death: the flock frees when the host tree dies while
  container-side pg_regress survives — the straggler mechanism, now
  twice-observed
status: In Progress
assignee:
  - '@architect'
created_date: '2026-08-27 16:44'
updated_date: '2026-08-27 19:46'
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
<!-- COMMENTS:END -->
