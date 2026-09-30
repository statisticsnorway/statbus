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
| 1 | cut oracles: `go-test`, `fast-tests`, `app_build_and_lint` | the code at the commit: Go CLI units (including the live twins), the fast SQL suite (migrations, temporal tables, import, worker), the Next.js build and lint | GitHub runners | release preflight refuses to tag without them; run `./dev.sh continous-integration-test` locally for the Fast Tests equivalent |
| 2 | `release.yaml` | six `sb` binaries and six ghcr images exist for the tag; released migrations are immutable | GitHub runners, ~5 min | the tag push |
| 3 | `test-hardening` | the shipped images and compose posture, and `install.sh` end to end against a pinned version on a runner | GitHub runner, ~12 min | the tag push |
| 4 | smoke `0-happy-install` | an empty prepared Ubuntu 26.04 LXD guest in NSO standalone mode (default stable channel) runs the candidate’s shipped `install.sh --non-interactive` with `STATBUS_INSTALL_VERSION=<tag>` through FRESH, using explicit deployment answers, pre-provisioned `TLS_CERT_FILE`/`TLS_KEY_FILE` and signer consent; proves mode/channel, candidate binary/ledger identity and CA-verified HTTPS health, then separately applies operator tuning and verifies restarted consumers, then promotes its own checkpoint for rung 7's fault fleet to consume (STATBUS-425) | one LXD fork on the shared fleet host, ~13 min | the tag push, via the orchestrator |
| 5 | smoke `0-happy-upgrade` | a standalone LXD guest with pre-provisioned certificate files installs the newest stable below the candidate using the legacy baseline helper, then the real upgrade service, judged by the RELEASED binary, takes it to the candidate with data intact and CA-verified HTTPS health. Temporary v2026.09.0 exception: switch baseline installation to FRESH `install.sh` from the first stable carrying the unattended config seam. This cell does not yet prove autonomous latest-stable selection | one LXD fork on the shared fleet host, ~15 min | same |
| 6 | dev canary | `statbus_dev` on niue takes the candidate through its own upgrade service, like a customer box | no VM, ~2 min | same; never skipped |
| 7 | LXD fault fleet (default checkpoint tree) | pristine Ubuntu guests harden and install the candidate's released assets into mode-specific bases; installed forks execute every default fault scenario (excluding `0-happy-*` and `HARNESS_SKIP_DEFAULT`) with its original assertions. Happy install/upgrade are proven separately by VM smoke (rungs 4–5); base construction proves the guest install prerequisite, not a happy-upgrade result. A nonempty complete PASSED LXD workflow at the RC commit is required for stable promotion; SUPERSEDED never promotes | one on-demand Ubuntu 26.04 host with a Btrfs LXD pool; rc.11 measured 36 min cold-to-verdict | same, after dev canary |
| 8 | upgrade-arc fleet (32 arcs) | the upgrade killed or broken at one exact point, then recovered: pre-swap (backup, checkout, binary swap), post-swap (mid-migration, mid-transaction, between migrations, after commit, container restart, OOM, timeout, ceiling), watchdog and proxy, rollback kills and resurrection, park and un-park, restore reattempt, transient DB backoff, cross-version rename handoff, plus the `working` and `failing` lineage fixtures | 32 LXD forks of the shared fleet box, arc jobs `max-parallel: 4`, guests bounded on the host (`LXD_HOST_SLOTS`, default 8); wall time not yet measured | same |
| 9 | Norway canary | a person installs the candidate on `rune` deliberately, against an observation card | human | the King, never automated |
| 10 | `./sb release stable` | reads rungs 2 to 9 at the exact commit and promotes the LATEST rc | laptop | the King |

Rungs 4 and 5 share one selected LXD scenario matrix run and one fleet lease (STATBUS-425: moved off fresh Hetzner VMs onto the same LXD fleet host rung 7 uses); rung 8 (arcs) runs as one job per arc on the same LXD host, concurrently with rung 7 (both start after the dev canary; the host slot semaphore bounds total guests). Each candidate-A arc forks smoke's literal `installed-<candidate>-standalone` (full `HEAD == BASE_SHA` re-verified in the fork; a missing or non-smoke checkpoint fails loud, no pristine reinstall). The two historical bases (pre-rename 730b5001c, schema-floor d53731ec) fork an exact-SHA checkpoint built once from smoke's hardened base. Release metadata is never rewritten. Known unresolved: smoke's checkpoint is installed by the tagged installer, so A's row is `prerelease` where a per-commit install records `commit`; `rollback-pair-terminal` and `restore-broke-reattempt` are expected to hit the STATBUS-435 supersession mismatch until the owner's contract decision, and this stays a stable-gate blocker, not something the harness masks. Rung 7 is the independent LXD checkpoint-tree fault gate, now fed by rung 4/5's own checkpoints rather than building its own. The former 40 GB disk scenario was dropped (owner, 2026-09-28); STATBUS-425 moving smoke itself onto LXD removed the last real 40 GB disk in the ladder (the revisit condition named in that ruling), so its policy is unit-tested only (`TestSharedThresholdAcrossCallers`, `TestSavedDiskPolicySurvivesNewProcess`, `install_input_test.go`) with no end-to-end real-disk proof anywhere in the chain. Rungs 4 to 8 are driven in order by `release-fleet-orchestrator.yaml`, which
owns the tag. A failure at any rung stops the chain before the next, more
expensive rung is rented.

## What a rung may skip, and why that is safe

Rung 6 never skips: the product is proven on a real slot every time.

Fresh-install `0-happy-install` (rung 4 and its fleet cell) is candidate-specific:
it installs that version's release assets and requires evidence at the exact
candidate commit. A green install of an earlier version cannot be inherited,
even across an `app/`-only or `doc/`-only diff (STATBUS-369).

The VM cells in rungs 5 and 8 may inherit independent scenario evidence when nothing that scenario exercises changed. The LXD fault fleet at rung 7 does **not** inherit per-scenario VM marks: each candidate runs its full checkpoint tree, and stable promotion requires a successful LXD workflow at that exact RC commit. The VM coverage decision is ONE algorithm in ONE place:

- `cli/internal/release/coverage.go`, `DecideCoverage`: for a scenario and a
  target commit, look for green evidence at the commit; if none, walk back
  through prior rc tags (bounded, newest first) to the nearest one with
  evidence, and diff that tag against the target.
- `cli/internal/release/sensitivity.go`: the diff is judged for the full
  `Scenario{Name, Home}` with repository-root exact, directory-boundary, and
  anchored-prefix rules. Every match carries a stable reason (`box payload`,
  `shared controller`, `own scenario`, `shared harness input`, or `proof
  interpreter`). The checked file contains only rules broad across all homes;
  own scripts and home-specific controllers are derived in the same matcher.
- `./sb release covered <scenario> <commit>` is the same evaluator as a
  command (exit 0 covered, 1 must run, 2 undecidable, 64 usage, 69 stale
  binary). VM smoke and arc `covered-subset` and stable promotion use that evaluator too. The LXD whole-run gate does not.

The list, and what each entry stands for:

| broad rule | why every paid home cares |
|---|---|
| `install.sh` | the operator entry point every harness VM executes |
| `cli/` | conservative Work A policy for the one `sb` binary |
| `postgres/`, `caddy/` | the shipped images and the rendered Caddyfiles |
| `migrations/` | applied on the box |
| root `docker-compose.*` | what the box brings up |
| shared orchestrator/actions/workflows | how every paid proof is selected and made |
| `test/install-recovery/lib/`, `fixtures/` | conservative shared harness inputs |
| release interpreter and policy paths | evidence identity and inheritance meaning |

Fleet owns exactly `scenarios/<name>.sh`; arcs own exactly
`arcs/<name>-arc.sh`; Smoke owns its fixed two scenario scripts through its own
workflow wrapper. Sibling scenario contents do not invalidate each other.

`app/` and `doc/` are absent from the **VM scenario-inheritance policy** on purpose. The LXD suite is candidate-pinned and cannot skip merely because that policy calls a change test-irrelevant. VM smoke and upgrade arcs retain their path-sensitive decisions; rung 6 remains mandatory. `cli/cmd/sensitive_paths_list_test.go`
pins the real list against every artefact the box executes, so an entry
cannot be lost silently.

## Reading a candidate

```
GITHUB_TOKEN=$(gh auth token) ./sb release stable        # the whole ladder, refuses until green
./sb release covered --workflow test-smoke.yaml 0-happy-install <sha>   # one scenario in one home (the happy slugs exist in both smoke and fleet)
```

The gate prints one line per rung: green at the sha, or covered by a named
earlier tag, or the exact run to look at. "15/15 proven here, 0 inherited"
means every scenario ran at this commit; "covered by v2026.09.0-rc.13"
means it rode an earlier proof and names it.

Before asking the owner to cut, run `./sb release check`: it runs every
prerelease preflight gate exactly as `prerelease` does, prints the same
table, and exits 1 on any red — but it tags nothing, pushes nothing, and
writes no file under `tmp/`. So the coordinator or a worker can see and fix
a red gate without also being the person who cuts. `prerelease` is
`check` plus the tag; one code path, so what `check` says is what
`prerelease` decides.

## Served installer compatibility floor

The served `install.sh` is an external compatibility surface. Until it has
downloaded or extracted the target `sb` and atomically placed that binary in
`~/statbus/sb`, it may use only commands and behavior available in the oldest
supported source release. An executable already on the box is the old product,
not evidence that a newer command or flag exists.

Bootstrap tag and commit fetching therefore uses plain Git under the installer's
own `GIT_TERMINAL_PROMPT=0` environment. It must not call the box binary's hidden
`repo-fetch` command. `cli/cmd/bootstrap_fetch_delegation_test.go` inventories
every executable `./sb` call in the served script, and
`test/install/install-git-fetch-compatibility-test.sh` supplies the compatibility
floor fixture: the `v2026.09.1-rc.18` command shape, whose `repo-fetch` rejects
`--tags` with EX_USAGE (64). The fixture proves plain Git fetches the tag without
calling that old binary and proves usage errors are not retried as transient
network failures.

The paid upgrade smoke still chooses the newest stable release below the target
as its source installation. The rc.18 fixture is the older command-surface floor
for the served-script bootstrap regression, not a replacement for that real-VM
previous-stable run.

## Known gaps (tickets)

- STATBUS-350 Option A is implemented: one selector-driven smoke matrix, native
  bounded fleet queue, occupied-group orchestrator refusal, rare-race native
  waiting, and shared pre-side-effect revalidation for orchestrated paid runs.
  Live acceptance remains the later batch RC, not an implementation-time paid
  run.
- STATBUS-351 is implemented: rungs 7 and 8 now ask the shared coverage
  authority per scenario, dispatch only uncovered subsets, fail open to the
  full suite when the optimizer cannot decide, and expose a separate red
  coverage-question health signal. Live acceptance remains the later batch RC.
- STATBUS-352 Work package A is implemented: sensitivity is workflow-aware,
  sibling scripts are narrow, all invalidating paths carry reasons, and
  undecidable questions fail open to a full suite with a red health diagnostic.
  `cli/` deliberately remains broad until the separately gated Work B prototype.
- STATBUS-353: per-scenario Go coverage profiles as evidence, so a diff is
  sensitive only if it touches functions that scenario actually ran.
- Smoke, faults and arcs share one LXD box (`ccx33`). Concurrency is bounded on the host by `LXD_HOST_SLOTS` (default 8 guests, `ops/lxd-fleet/admission.sh`) and by arc `max-parallel: 4`. Whether 8 guests fit the box's 60 GiB pool and RAM, and the concurrent wall time, are unmeasured until the first RC runs through this path; a larger box (STATBUS-423) is the lever if not.
