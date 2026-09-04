# The release ladder: what a candidate must prove, and what it may skip

Every release candidate climbs the same ladder. Each rung proves one thing
the rungs below cannot. A candidate is promotable when every rung the
machine can decide is green at the candidate's exact commit and the human
rung has been signed. `./sb release stable` reads the ladder and refuses
until that is true.

Sister documents: [release-workflow-gates.md](release-workflow-gates.md)
(how a gate reads GitHub), [install-upgrade-testing.md](install-upgrade-testing.md)
(why the VM rungs cannot be reasoned about, only run),
[releases.md](releases.md) (how to cut).

## The rungs

| # | rung | proves | cost | when it runs |
|---|---|---|---|---|
| 1 | cut oracles: `go-test`, `fast-tests`, `pg_regress`, `app_build_and_lint` | the code at the commit: Go CLI units (about 1000, including the live twins), the SQL suite (migrations, temporal tables, import, worker), the Next.js build and lint | GitHub runners, ~10 min | every push to master; `./sb release rc` refuses to tag without them |
| 2 | `release.yaml` | six `sb` binaries and six ghcr images exist for the tag; released migrations are immutable | GitHub runners, ~5 min | the tag push |
| 3 | `test-hardening` | the shipped images and compose posture, and `install.sh` end to end against a pinned version on a runner | GitHub runner, ~12 min | the tag push |
| 4 | smoke `0-happy-install` | a fresh Ubuntu VM runs the real `install.sh` and ends with a healthy StatBus at the candidate | 1 VM, ~13 min | the tag push, via the orchestrator |
| 5 | smoke `0-happy-upgrade` | a VM installs the newest stable below the candidate, then the real upgrade service, judged by the RELEASED binary, takes it to the candidate with data intact | 1 VM, ~15 min | same |
| 6 | dev canary | `statbus_dev` on niue takes the candidate through its own upgrade service, like a customer box | no VM, ~2 min | same; never skipped |
| 7 | install-recovery fleet (15 scenarios) | the two smokes again, plus 13 failure injections during install: advisory lock too early, concurrent install, stale flag handoff, startup timeout, worker DDL deadlock after the swap, bool/text regression, drifted systemd unit, seed on a populated DB, and the five stage kills (migrate killed, pool exhaustion, systemd failed, advisory zombie, worker busy). Each must recover to a healthy box or refuse with a reason | 15 VMs, ~60 min at max-parallel 3 | same |
| 8 | upgrade-arc fleet (32 arcs) | the upgrade killed or broken at one exact point, then recovered: pre-swap (backup, checkout, binary swap), post-swap (mid-migration, mid-transaction, between migrations, after commit, container restart, OOM, timeout, ceiling), watchdog and proxy, rollback kills and resurrection, park and un-park, restore reattempt, transient DB backoff, cross-version rename handoff, plus the `working` and `failing` lineage fixtures | 32 VMs, ~2.5 h at max-parallel 3 | same |
| 9 | Norway canary | a person installs the candidate on `rune` deliberately, against an observation card | human | the King, never automated |
| 10 | `./sb release stable` | reads rungs 2 to 9 at the exact commit and promotes the LATEST rc | laptop | the King |

Rungs 4 and 5 share one selected matrix run and one fleet lease. Rungs 4 to 8 are driven in order by `release-fleet-orchestrator.yaml`, which
owns the tag. A failure at any rung stops the chain before the next, more
expensive rung is rented.

## What a rung may skip, and why that is safe

Rung 6 never skips: the product is proven on a real slot every time.

Rungs 4, 5, 7 and 8 exist to prove install, upgrade and recovery. Those only
change when files the box executes change. So a scenario proven at an
earlier candidate still holds for a later one if nothing it exercises
changed in between. That decision is ONE algorithm in ONE place:

- `cli/internal/release/coverage.go`, `DecideCoverage`: for a scenario and a
  target commit, look for green evidence at the commit; if none, walk back
  through prior rc tags (bounded, newest first) to the nearest one with
  evidence, and diff that tag against the target.
- `cli/internal/release/sensitivity.go`: the diff is judged against
  `ops/release/upgrade-sensitive-paths.txt` (substring containment, on
  purpose over-inclusive). If no changed file matches, the scenario is
  covered and rides the earlier proof; the output names the tag it rides.
- `./sb release covered <scenario> <commit>` is the same function as a
  command (exit 0 covered, 1 must run, 2 undecidable, 64 usage, 69 stale
  binary). CI calls it; the stable gate calls the library directly. There
  is no second implementation.

The list, and what each entry stands for:

| entry | why the box cares |
|---|---|
| `install.sh` | the operator entry point every harness VM executes |
| `cli/` | `./sb`: install, upgrade service, migrate, config |
| `postgres/`, `caddy/` | the shipped images and the rendered Caddyfiles |
| `migrations/` | applied on the box |
| `docker-compose` | what the box brings up |
| `ops/` | the systemd unit, the box scripts, and this list |
| `test/install-recovery/` | the harness itself: a changed assertion is a changed proof |
| `upgrade-arc-harness.yaml`, `images.yaml` | how the proof and the images are made |

`app/` and `doc/` are absent on purpose. A candidate that changes only the
product skips every VM rung and is proven by rung 6. `cli/cmd/sensitive_paths_list_test.go`
pins the real list against every artefact the box executes, so an entry
cannot be lost silently.

## Reading a candidate

```
GITHUB_TOKEN=$(gh auth token) ./sb release stable        # the whole ladder, refuses until green
./sb release covered 0-happy-install <sha>               # one scenario, says where its proof comes from
```

The gate prints one line per rung: green at the sha, or covered by a named
earlier tag, or the exact run to look at. "15/15 proven here, 0 inherited"
means every scenario ran at this commit; "covered by v2026.09.0-rc.13"
means it rode an earlier proof and names it.

## Known gaps (tickets)

- STATBUS-350 is implemented: one selector-driven smoke matrix, native bounded
  fleet queue, and owner-aware orchestrator dispatch. Live acceptance remains
  the later batch RC, not an implementation-time paid run.
- STATBUS-351: rung 7 never asks `covered` (always rents 15 VMs) and rung 8
  asks a bash one-hop rule instead of the library; make every fleet rung
  dispatch only the uncovered subset.
- STATBUS-352: the list says `cli/` and `test/install-recovery/`, so a change
  to release tooling or to a sibling scenario's script re-proves everything;
  derive the box-side Go set with `go list -deps` and make each scenario
  sensitive only to what it executes.
- STATBUS-353: per-scenario Go coverage profiles as evidence, so a diff is
  sensitive only if it touches functions that scenario actually ran.
- The fleets run at `max-parallel: 3` because the Hetzner project quota
  (servers and primary IPs) was hit at 8. Raising the quota is the single
  largest wall-clock lever: rung 8 at 3 wide is ~2.5 h, at 8 wide it would
  be under 1 h.
