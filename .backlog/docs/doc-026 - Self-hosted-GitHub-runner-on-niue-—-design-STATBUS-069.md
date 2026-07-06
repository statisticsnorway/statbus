---
id: doc-026
title: Self-hosted GitHub runner on niue — design (STATBUS-069)
type: specification
created_date: '2026-07-06 19:40'
tags:
  - ci
  - ops
  - niue
  - design
  - STATBUS-069
---
# Self-hosted GitHub runner on niue — design (STATBUS-069)

**Status: DESIGN ONLY — awaiting the King's approval. No server writes, no workflow edits, no runner registration have been made.**

## The problem, in one paragraph

CI jobs that SSH into niue (the upgrade poke to all 7 cloud slots, the pg_regress suite) run on GitHub's shared cloud runners, whose IP ranges live in the same Azure blocks that SSH attackers rent. niue's crowdsec (confirmed running: crowdsec.service + crowdsec-firewall-bouncer.service) subscribes to the community blocklist, which regularly bans those ranges — so our own CI intermittently cannot reach our own server, and gated jobs fail for reasons that have nothing to do with the code. Whitelisting GitHub's ranges was rejected by the King (it would re-open the exact door the blocklist closes). The fix is to move the SSH **client** onto niue itself: a self-hosted GitHub runner in a container, so CI traffic to niue never crosses the public SSH gate at all.

## The core design decision: the runner is a network-position fix, not a privilege change

The runner does exactly one new thing: it runs the workflow's steps **from niue instead of from Azure**. Everything else stays as it is today — the same per-slot SSH users (statbus_dev … statbus_jo, statbus_test), the same SSH key, the same sshdo/command allowlists, the same scripts. The workflows keep their `ssh` steps; only the connection now originates on the box (via the Docker host gateway to niue's own sshd) instead of crossing the internet. This deliberately rejects the tempting "stronger" variant — letting the runner execute directly inside the slot users' contexts — because that would replace today's well-understood SSH privilege boundary with container-to-host privilege plumbing (mounts, sudo, or the docker socket), a much larger blast radius for zero additional benefit.

## 1. Shape

- **Image**: GitHub's official `ghcr.io/actions/actions-runner`, pinned by digest, plus a ~20-line entrypoint script of ours that fetches a fresh registration token at start (from a fine-grained PAT, see §2) and runs the runner in **ephemeral mode** (`--ephemeral`: the runner takes exactly one job, exits, and the container restarts clean — no state accumulates between jobs). The popular community image (myoung34/docker-github-actions-runner) automates the same thing but means running a third party's image on our production host; the official image + our own thin script keeps the supply chain to GitHub + us.
- **Where it lives**: its own compose project at `/home/github-runner/` under a **new dedicated user `github-runner`** — a sibling of the per-slot homes, NOT inside any statbus slot and NOT under devops. One `docker-compose.yml`, one `.env` (the PAT), one entrypoint script.
- **Container confinement**: runs as a non-root user inside the container; **no docker socket mount** (the jobs we move don't build or run containers — they SSH); no host mounts beyond its own named work volume; default bridge network. `extra_hosts: niue-host:host-gateway` gives it a route to niue's own sshd — that route still requires the per-slot SSH key to do anything.
- **Resource caps**: `cpus: 2`, `mem_limit: 2g`. The runner-side work is trivial (an SSH client; the heavy lifting — pg_regress — happens in statbus_test's checkout exactly as today). niue has 16 cores / 30 GB with ~20 GB available; the cap makes a runaway job unable to disturb the production slots.
- **Restart policy**: `restart: always`. Combined with ephemeral mode this is also the re-registration loop: job finishes → runner deregisters → container restarts → fresh token → fresh registration.
- **One runner, one job at a time.** Our niue-bound jobs are short (the notify legs are 30-second jobs; pg_regress is already serialized by its own concurrency group). If queueing ever becomes a real wait, adding a second replica is a one-line compose change — start with one.

## 2. Security (the load-bearing part)

- **Registration scope: REPO-scoped** to statisticsnorway/statbus only — never org-scoped. An org-scoped runner would be visible to every repository in statisticsnorway; a repo-scoped one can only ever receive this repo's workflows.
- **Secret handling**: registration tokens themselves expire in one hour, so the box holds a **fine-grained PAT** whose ONLY permission is self-hosted-runner administration on this ONE repository, stored in `/home/github-runner/.env`, owner-read-only, never in the repo or the compose file. Rotation is mechanical: regenerate the PAT (90-day expiry recommended so rotation is forced, not forgotten), update the one file, restart the container. If the PAT ever leaks, its worst case is runner registration/deregistration on one repo — it cannot read code, secrets, or other repos.
- **Label strategy**: the runner registers with labels `self-hosted, niue`. Only jobs that say `runs-on: [self-hosted, niue]` can land on it; everything else in the repo continues to say `ubuntu-latest` and never touches the box.
- **The fork-PR hazard — this is the one rule that must never be broken.** The repo is PUBLIC (verified: `gh api repos/statisticsnorway/statbus` → `"visibility": "public"`). For `pull_request`-triggered workflows, GitHub uses the workflow file from the PR's merge ref — meaning a fork PR can MODIFY the workflow, including its `runs-on` and its steps. A fork PR that lands on a self-hosted runner is arbitrary third-party code executing on our production host. Three defenses, all applied:
  1. **Structural (primary): no `pull_request`-triggered job ever gets the self-hosted labels.** pg_regress is the only affected workflow with a `pull_request` trigger; it is split into two jobs — the PR leg stays on `ubuntu-latest` exactly as today (where fork PRs already fail harmlessly for lack of secrets), and only the `push`/`workflow_run`/`workflow_dispatch` legs (which run our own master-branch code) move to `[self-hosted, niue]`.
  2. **Repo setting (backstop)**: raise Actions approval to "Require approval for ALL outside collaborators" (the default only gates first-time contributors — a previously-merged contributor's fork would run unapproved). This is a one-click setting; verify it at build time (it is not readable via the API surface we checked).
  3. **Containment (last resort, never relied on)**: ephemeral runner, no docker socket, resource caps, non-root — a mistake has a bounded blast radius, but the design treats defenses 1–2 as the actual guarantee.
- **What we accept, stated honestly**: our own master-branch and workflow_run workflows execute on niue via this runner. That is the SAME trust we already extend today — CI already executes commands on niue through SSH_KEY + the sshdo/github-run.sh allowlists; the runner moves the client, not the authority. The per-slot allowlists remain the authorization boundary for what CI may actually do on the box.
- **crowdsec interaction**: the runner's SSH connections originate from the Docker bridge (an RFC1918 address). To prevent the runner from ever self-banning (e.g. a key mishap producing repeated auth failures from the bridge IP), whitelist the Docker bridge subnet in crowdsec. This is categorically different from whitelisting GitHub's public ranges: nothing on the public internet can source traffic from the host's own private bridge, so it re-opens no external door.

## 3. Migration — which jobs, in what order

The affected class is "workflows that SSH to niue": notify-all-clouds.yaml (7 matrix legs), pg_regress.yaml, seq-logserver.yaml, docker-maintenance.yaml. Deploy workflows targeting rune.statbus.org are a different host and stay as they are (if rune runs the same crowdsec posture, that is a separate, later decision — noted, not designed here).

1. **Stand up the runner idle** — registered, labeled, receiving nothing. Zero workflow changes. Observe it stay healthy for a day.
2. **Move notify-all-clouds first** — the lowest-risk canary: 30-second jobs, failure is visible and non-blocking, and it runs on every master push so we get immediate, frequent evidence. Change per job: `runs-on: [self-hosted, niue]` + SSH host becomes the host-gateway alias. Everything else (user, key, script) unchanged.
3. **Move pg_regress's trusted legs** — the two-job split from §2: PR leg stays hosted, master/dispatch leg moves. This is the job the flapping actually gates, so it is the payoff step.
4. **seq-logserver + docker-maintenance ride along** after a week of green — same one-line pattern.
5. **Rollback at every step is one line per workflow**: revert `runs-on` to `ubuntu-latest` and the host back to `niue.statbus.org` — the hosted path continues to exist and work (modulo the original intermittent bans) the whole time.

## 4. Operations

- **Updates**: the runner version is pinned via the image digest; GitHub deprecates old runner versions with a grace window, so the image bump rides the existing monthly docker-maintenance cadence (same habit as the other pinned images). Ephemeral mode means an update is just: bump digest, `docker compose up -d` — no draining logic needed.
- **Knowing it's down — without losing today's loud signal**: a job targeting an offline self-hosted runner does not fail fast; it QUEUES (up to 24 h) — silently, which would be a regression from today's immediately-red notify job. So notify-all-clouds gains one tiny **hosted** canary job (runs on `ubuntu-latest`, needs no secrets beyond a read-only runner query): it asks the GitHub API whether the niue runner is online and FAILS LOUDLY if not. Net: runner down → the very next master push goes red with a message naming the runner, preserving exactly the signal property the King values, with better wording than today's bare exit 1.
- **On the box**: `restart: always` + ephemeral means the steady state self-heals across reboots and crashes; `docker ps` on niue shows it like any other service; its logs are one `docker logs` away.

## 5. What we deliberately do NOT do

- **We do not whitelist GitHub's runner IP ranges in crowdsec.** The King rejected this explicitly: those ranges are banned by the community precisely because attackers operate from them; whitelisting would re-open the SSH attack door for everyone renting the same cloud. This design exists so that nobody ever "simplifies" to that. (The only crowdsec change is the private Docker-bridge whitelist in §2, which no external party can use.)
- **We do not register the runner org-wide**, do not mount the docker socket, do not let any `pull_request`-triggered job carry the self-hosted labels, and do not give the runner any slot-user privilege — the SSH keys and allowlists remain the sole authority for actions on the box.
- **We do not build a VPN/tailnet for CI→niue** (considered and rejected): it solves the same reachability problem with a whole new trust fabric, key sprawl, and a standing network path — heavier than a runner and it still leaves CI dependent on the public gate's disposition.

## Prior art checked

Read-only inspection of niue (2026-07-06) found no existing runner to pattern-match (the `seq` container is the log server; `/home/devops/bin/github-run.sh` is the SSH command-allowlist wrapper — kept, unchanged, as the authorization layer). The Brovs project uses Jenkins with its own agent, a different architecture; this design follows GitHub's official self-hosted runner + compose, which is the standard shape for this exact problem.

## Verification (when built)

1. Runner registers, shows online with labels `self-hosted, niue`; survives a container restart and a box reboot re-registering itself.
2. A test dispatch of notify-all-clouds lands on the runner and the `./sb upgrade check` legs go green from the box (no public SSH hop — confirm in sshd logs the connection source is the bridge).
3. A deliberate runner stop turns the canary job red on the next push with the actionable message (the loud-signal property).
4. A fork-PR dry run (from a scratch fork) confirms pg_regress's PR leg runs hosted and NOTHING lands on the self-hosted runner.
5. Several days of master pushes with zero `dial 162.55.61.141:22: i/o timeout` failures — the original symptom gone.
