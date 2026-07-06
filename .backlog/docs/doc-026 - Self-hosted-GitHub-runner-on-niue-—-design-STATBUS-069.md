---
id: doc-026
title: Self-hosted GitHub runner on niue — design (STATBUS-069)
type: specification
created_date: '2026-07-06 19:40'
updated_date: '2026-07-06 22:58'
tags:
  - ci
  - ops
  - niue
  - design
  - STATBUS-069
---
# Self-hosted GitHub runner on niue — design v2 (STATBUS-069)

**Status: DESIGN ONLY — awaiting the King's approval. No server writes, no workflow edits, no runner registration have been made.**

**v2 (2026-07-07): reconciled against the operator's PROVEN prior art — a production runner of the same pattern on another (private) deployment, artifacts reviewed first-hand. The prior art confirms the v1 core (compose on the box, non-root, no docker socket, resource caps, outbound-only long-poll, selective labels, SSH targets resolved to host-gateway, CrowdSec untouched). Where the two differed, the deltas below are RULED, each with its reason. One v1 posture that must NOT be relaxed toward the prior-art runner is called out explicitly (fork PRs — §Deltas item 5).**

## The problem, in one paragraph

CI jobs that SSH into niue (the upgrade poke to all 7 cloud slots, the pg_regress suite) run on GitHub's shared cloud runners, whose IP ranges live in the same Azure blocks that SSH attackers rent. niue's crowdsec (confirmed running: crowdsec.service + crowdsec-firewall-bouncer.service; 38,822 active community-list bans, hundreds inside GitHub's Azure prefixes — ticket comment #1) regularly bans those ranges — so our own CI intermittently cannot reach our own server, and gated jobs fail for reasons that have nothing to do with the code. Whitelisting GitHub's ranges was rejected by the King (it would re-open the exact door the blocklist closes). The fix is the King's proven pattern: move the SSH **client** onto niue itself — a self-hosted GitHub runner in a container — so CI traffic to niue never crosses the public SSH gate at all.

## The core design decision: the runner is a network-position fix, not a privilege change

The runner does exactly one new thing: it runs the workflow's steps **from niue instead of from Azure**. Everything else stays as it is today — the same per-slot SSH users (statbus_dev … statbus_jo, statbus_test), the same SSH key, the same sshdo/command allowlists, the same scripts. The workflows keep their `ssh` steps; only the connection now originates on the box (via the Docker host gateway to niue's own sshd) instead of crossing the internet. This deliberately rejects the tempting "stronger" variant — letting the runner execute directly inside the slot users' contexts — because that would replace today's well-understood SSH privilege boundary with container-to-host privilege plumbing (mounts, sudo, or the docker socket), a much larger blast radius for zero additional benefit. The prior art embodies the same principle: its deploy SSH resolves the target names to the host itself, and the box's SSH protection stays fully enforced for the outside world.

## Deltas from v1, reconciled against the prior art — the ruled choices

1. **PERSISTENT registration replaces v1's ephemeral mode — ADOPT the prior art.** v1 chose `--ephemeral` with a durable fine-grained PAT on the box minting a fresh token per restart. The prior art instead registers ONCE with a short-lived (1-hour) registration token and persists the registration in a named `runner-state` volume across restarts and recreates. The tradeoff, named: ephemeral buys per-job state freshness — worthless for our jobs, which are 30-second SSH legs that build nothing and cache nothing — and costs a STANDING ADMIN SECRET on the box (the PAT: runner add/remove authority, needs rotation, can leak). Persistent costs a `.credentials` file in a volume (one runner's identity on one repo — strictly weaker than the PAT) and buys: no durable secret to rotate or leak (the 1h token is worthless minutes after use), a simpler entrypoint, and fidelity to a pattern already carrying production deploys. Persistent wins on both security and simplicity. If the state volume is ever lost, recovery is one one-tap token mint (`gh api -X POST repos/statisticsnorway/statbus/actions/runners/registration-token --jq .token`) — not a crisis. v1's PAT-rotation machinery is DELETED from this design.
2. **Updates via a BOX-LOCAL systemd timer — ADOPT the prior art, replacing v1's docker-maintenance-cadence idea.** Weekly (Sunday 03:17, `Persistent=true` — the same class of quiet slot the prior art uses, an hour after niue's own seq refresh window): `docker compose build --pull` then recreate ONLY if the image changed; SKIP outright if a job is executing right now (`pgrep -f Runner.Worker` — the worker process exists only while a job runs). The trigger is box-local ON PURPOSE: a GitHub-hosted job cannot recreate the container it is running in, and (the prior art's second reason) a GitHub-triggered recreate would re-roll the runner-IP dice — for us that second reason vanishes once everything is migrated, but the first stands alone. The timer's `Persistent=true` catches a box that was off over the window.
3. **Image tracks `:latest`, not a digest pin — ADOPT the prior art, reversing v1.** v1's digest pin was theater on this particular image: the runner SELF-UPDATES in place regardless (GitHub refuses connections from old runner versions), so the digest pins nothing that matters, and the weekly timer is the deliberate refresh. Supply-chain pinning moves to where the third-party risk actually lives: **marketplace ACTIONS are pinned to commit SHAs** in every workflow that runs self-hosted (delta 4).
4. **SHA-pin marketplace actions — ADOPT into the migration.** Every workflow that gains the self-hosted labels pins its actions to full commit SHAs (for us that is `appleboy/ssh-action`, today at the mutable tag `@v1.2.0`) — a tag can be moved to malicious code by a compromised action repo; a SHA cannot. This lands in the same commit as each workflow's migration.
5. **The prior art's fork-PR posture does NOT transfer — v1's triple defense stays load-bearing, stated so nobody imports the laxer posture along with the mechanics.** The prior-art repo is PRIVATE: no fork PRs, so it never needed a fork defense. statbus is PUBLIC (verified via the API). The one unbreakable rule stands exactly as v1 wrote it: no `pull_request`-triggered job ever carries the self-hosted labels (§2 below).
6. **Residual-risk framing — matches, cite theirs.** The prior-art project accepted the same trade this design accepts: the container boundary (non-root, no socket, no new inbound port, caps) is the isolation, and the marginal alternative — a separate paid VM per concern — was rejected there too. Same host, same reasoning, now with a production track record.
7. **Three paid-for gotchas from the prior-art build — folded into the build notes so we do not pay for them twice:**
   (a) **Named-volume mountpoints inherit image ownership**: every directory a volume mounts over must be pre-created OWNED BY the runner user IN THE DOCKERFILE (`mkdir -p … && chown runner:runner …` before `USER runner`), else the volume initializes root-owned and the non-root runner cannot write — on the prior art this produced an "already configured" restart loop and `UnauthorizedAccessException` in `_work`.
   (b) **Tool install dirs must point into the work volume** (the prior art's tool-install-dir lesson): any action that installs a toolchain defaults to a root-owned system path. Our SSH-leg jobs install nothing today; the note stands as the rule to apply THE DAY a self-hosted job first uses a setup-* action.
   (c) **`gh run watch --exit-status` returned 0 for a FAILED run** on the prior art — never gate anything on it; always read `.conclusion` from the API explicitly. (Our own committed CI already does this right — see the harness-sweep finding on the ticket.)
8. **Workflows keep their `host:` line unchanged — sharpened by the prior art's extra_hosts pattern.** It maps its real deploy hostnames to `host-gateway`, so workflow files keep using the real names. We do the same: `extra_hosts: "niue.statbus.org:host-gateway"`. The per-workflow migration diff shrinks to the `runs-on` line (plus the action SHA-pin) — the SSH host, user, key, and script are byte-identical to today.

## 1. Shape

- **Image**: `ghcr.io/actions/actions-runner:latest` (tracking rationale: delta 3) + a thin Dockerfile layer of ours: install the few packages the jobs need (openssh-client, ca-certificates; extend only when a job proves the need), copy the entrypoint, and **pre-create every volume mountpoint owned by the runner user** (delta 7a). Entrypoint = the prior art's proven shape: restore persisted registration from `/runner-state` if present; else register with the one-time `RUNNER_TOKEN` from `.env` and persist; else fail with the exact mint command in the error text.
- **Where it lives**: its own compose project at `/home/github-runner/` under a **new dedicated user `github-runner`** (docker group, no sudo — mirrors the prior art's dedicated user) — a sibling of the per-slot homes, NOT inside any statbus slot and NOT under devops.
- **Container confinement**: the image's non-root `runner` user; **no docker socket mount**; no host mounts — only named volumes (`runner-state` for registration; `runner-work` for the job workspace); default bridge network; **no new inbound port** (the runner long-polls GitHub outbound only). `extra_hosts: "niue.statbus.org:host-gateway"` routes the workflows' existing SSH target to the box itself.
- **Resource caps**: `cpus: 2`, `mem_limit: 2g` (the prior art runs 3.0/6g because its jobs BUILD a toolchain; ours only SSH — capped smaller on a busier host: niue has 16 cores / 30 GB serving 7 production slots).
- **Restart policy**: `restart: unless-stopped` (the prior art's choice; registration persistence makes restart semantics boring).
- **One runner, one job at a time.** Our niue-bound jobs are short (30-second notify legs; pg_regress is already serialized by its own concurrency group). A second replica is a one-line change if queueing ever hurts — start with one.

## 2. Security (the load-bearing part)

- **Registration scope: REPO-scoped** to statisticsnorway/statbus only — never org-scoped (an org-scoped runner is visible to every repository in statisticsnorway).
- **Secret handling (v2, per delta 1)**: NO durable secret on the box. Registration happens once, with a 1-hour single-purpose token minted at setup (`gh api -X POST repos/statisticsnorway/statbus/actions/runners/registration-token`) and placed in `.env` for the first boot only — worthless once used or expired. What persists is the runner's own `.credentials` in the `runner-state` volume: the identity of one runner on one repo, readable only by root and the github-runner user on the box. Worst case if exfiltrated: an attacker can impersonate this runner and receive this repo's queued self-hosted jobs — mitigated by the same rule that governs everything else here: only trusted-trigger jobs ever target these labels.
- **Label strategy**: registers with labels `self-hosted, niue`. Only jobs that say `runs-on: [self-hosted, niue]` can land on it; everything else stays `ubuntu-latest` and never touches the box.
- **The fork-PR hazard — the one rule that must never be broken (unchanged from v1; delta 5 records why the prior art's laxer posture does not transfer).** The repo is PUBLIC. For `pull_request`-triggered workflows GitHub uses the workflow file from the PR's merge ref — a fork PR can MODIFY the workflow, including `runs-on` and steps. A fork PR landing on a self-hosted runner is arbitrary third-party code on our production host. Three defenses, all applied:
  1. **Structural (primary): no `pull_request`-triggered job ever gets the self-hosted labels.** pg_regress (the only affected workflow with a PR trigger) splits: the PR leg stays on `ubuntu-latest` exactly as today (fork PRs already fail harmlessly there for lack of secrets); only the `push`/`workflow_run`/`workflow_dispatch` legs move.
  2. **Repo setting (backstop)**: raise Actions approval to "Require approval for ALL outside collaborators" (the default only gates first-time contributors). One click; verify at build time.
  3. **Containment (last resort, never relied on)**: non-root, no docker socket, no new inbound port, resource caps.
- **What we accept, stated honestly**: our own master-branch and workflow_run workflows execute on niue via this runner — the SAME trust we already extend today through SSH_KEY + the sshdo/github-run.sh allowlists, which remain the authorization boundary for what CI may actually DO on the box. Residual container-escape risk is accepted on the same grounds the prior-art project accepted it (delta 6).
- **crowdsec interaction**: the runner's SSH connections originate from the Docker bridge (RFC1918). Whitelist the bridge subnet in crowdsec so the runner can never self-ban (e.g. a key mishap producing repeated auth failures from the bridge IP). Categorically different from whitelisting GitHub's public ranges: nothing on the public internet can source traffic from the host's own bridge.

## 3. Migration — which jobs, in what order

The affected class is "workflows that SSH to niue": notify-all-clouds.yaml (7 matrix legs), pg_regress.yaml, seq-logserver.yaml, docker-maintenance.yaml, and the deploy-to-{dev,demo,tcc,ma,ug,et,jo}.yaml slot deploys. deploy-to-rune-no targets a different host and stays as-is (rune's own posture is a separate, later decision — noted, not designed here).

1. **Stand up the runner idle** — registered, labeled, receiving nothing. Zero workflow changes. Observe a day, including one weekly-timer pass.
2. **Move notify-all-clouds first** — the canary: 30-second jobs, visible non-blocking failure, runs on every master push. Per-workflow diff (delta 8): the `runs-on` line + SHA-pinning the ssh action. Host, user, key, script byte-identical.
3. **Move pg_regress's trusted legs** — the two-job split from §2. This is the job the flapping actually gates: the payoff step.
4. **seq-logserver, docker-maintenance, and the niue slot deploys ride along** after a week of green — same one-line pattern each.
5. **Rollback at every step is one line per workflow**: revert `runs-on` to `ubuntu-latest`. The hosted path continues to exist the whole time (modulo the original intermittent bans).

## 4. Operations

- **Updates (v2, per delta 2)**: the box-local weekly refresh — `gha-runner-upgrade.{service,timer}` pattern verbatim from the prior-art runner (Sunday 03:17, `Persistent=true`, runs as github-runner): `compose build --pull` → busy-skip if `Runner.Worker` is live → recreate only if the image changed → image prune. Registration survives recreates via the state volume; the runner also self-updates between refreshes.
- **Knowing it's down — without losing today's loud signal**: a job targeting an offline self-hosted runner QUEUES silently (up to 24 h) — a regression from today's immediately-red notify job if left alone. So notify-all-clouds gains one tiny **hosted** canary job: it asks the GitHub API whether the niue runner is online and FAILS LOUDLY naming the runner if not. Runner down → the very next master push goes red with an actionable message — the King's signal property, preserved with better wording than today's bare exit 1.
- **On the box**: `docker ps` shows it like any other service; logs are one `docker logs gha-runner` away; the weekly timer's journal shows every refresh decision.

## 5. What we deliberately do NOT do

- **We do not whitelist GitHub's runner IP ranges in crowdsec.** The King rejected this explicitly: those ranges are banned by the community precisely because attackers operate from them. This design exists so nobody ever "simplifies" to that. (The only crowdsec change is the private Docker-bridge whitelist in §2, unusable from outside.)
- **We do not register the runner org-wide**, do not mount the docker socket, do not let any `pull_request`-triggered job carry the self-hosted labels, do not keep a durable admin PAT on the box (v2 removed the need), and do not give the runner any slot-user privilege — SSH keys and allowlists remain the sole authority for actions on the box.
- **We do not update the runner from a GitHub workflow** (delta 2's reason: a job cannot recreate its own container) and **do not gate anything on `gh run watch --exit-status`** (delta 7c).
- **We do not build a VPN/tailnet for CI→niue** (considered and rejected): a whole new trust fabric and key sprawl for one hop, and CI would still depend on the public gate's disposition.

## Prior art

**the prior-art runner (the prior-art project, the prior-art project) is the proven reference** — same problem (CrowdSec CAPI banning Azure runner ranges), same host philosophy, in production for real deploys; this v2 adopts its registration persistence, box-local refresh timer, :latest-tracking rationale, extra_hosts pattern, and its three paid-for build gotchas, while keeping the public-repo fork defenses the prior-art runner never needed. Read-only inspection of niue (2026-07-06) found no existing runner on the box itself (the `seq` container is the log server; `/home/devops/bin/github-run.sh` is the SSH command-allowlist wrapper — kept, unchanged, as the authorization layer). niue's seq refresh precedent means the box already has the "weekly quiet-window container refresh" habit this design's timer extends.

## Verification (when built)

1. Runner registers, shows online with labels `self-hosted, niue`; survives container restart, container RECREATE (registration from the state volume — the delta-1 property), and a box reboot.
2. A test dispatch of notify-all-clouds lands on the runner and the `./sb upgrade check` legs go green from the box; sshd logs show the connection source is the docker bridge (no public hop).
3. A deliberate runner stop turns the hosted canary job red on the next push with the actionable message (the loud-signal property).
4. A fork-PR dry run (from a scratch fork) confirms pg_regress's PR leg runs hosted and NOTHING lands on the self-hosted runner.
5. One forced weekly-timer pass: busy-skip observed with a job running; recreate observed with a changed image; no-op observed with an unchanged one.
6. Several days of master pushes with zero `dial 162.55.61.141:22: i/o timeout` failures — the original symptom gone.
