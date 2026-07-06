# statbus GitHub Actions self-hosted runner (niue)

A containerized GitHub Actions runner that runs our niue-bound CI jobs **from
niue itself** instead of from a GitHub-hosted Azure runner. Azure runner IP
ranges intermittently sit on niue's CrowdSec community blocklist and get their
SSH dropped, so our own CI can't reach our own box (`dial …:22: i/o timeout`).
Moving the SSH *client* onto the box sidesteps the public SSH gate entirely; the
box's SSH protection stays fully enforced for everyone else.

**Full design + every ruled trade-off: doc-026 (STATBUS-069).** This directory is
the phase-1 deliverable: repo-side artifacts only. Nothing here touches niue,
registers a runner, or changes a live workflow — that is phase 2 (below), gated on
the architect's review.

## Files

| File | Role | Deployed to (phase 2) |
|---|---|---|
| `Dockerfile` | thin layer over `ghcr.io/actions/actions-runner:latest`: openssh-client + ca-certificates, entrypoint, pre-created runner-owned volume mountpoints | built on the box |
| `entrypoint.sh` | register-once-and-persist (restore from `runner-state`, else register with the 1h token, else fail with the mint command) | baked into the image |
| `docker-compose.yml` | the runner service: non-root, no docker socket, no inbound port, caps, `extra_hosts` host-gateway, named volumes | `/home/github-runner/docker-compose.yml` |
| `.env.example` | the `RUNNER_TOKEN` placeholder (first-boot only) | copied to `.env`, filled at deploy time |
| `gha-runner-upgrade.service` / `.timer` | weekly (Sun 03:17) box-local image refresh | `/etc/systemd/system/` |
| `upgrade-to-latest-gha-runner.sh` | the refresh: build --pull, busy-skip if a job runs, recreate only if the image changed | `/usr/local/bin/` |
| `notify-all-clouds.self-hosted.yaml` | **PROPOSED** phase-3 target of the notify workflow (raw-ssh legs + hosted canary). Kept out of `.github/workflows/` so it can't activate early. | replaces the live workflow, phase 3 |

## Security invariants (doc-026 §2 — never relax)

- **No docker socket**, non-root `runner` user, **no new inbound port** (outbound
  long-poll only), CPU/mem capped.
- **Repo-scoped** registration (`statisticsnorway/statbus`), never org-scoped.
- **No durable secret on the box.** The only secret is a **1-hour registration
  token** used once at first boot; what persists is the runner's own
  `.credentials` in the `runner-state` volume (one runner's identity on one repo).
- **The fork-PR rule is unbreakable:** no `pull_request`-triggered job ever carries
  the `self-hosted, niue` labels. statbus is a PUBLIC repo — a fork PR can rewrite a
  workflow, so a PR job on a self-hosted runner would be arbitrary third-party code
  on production. The notify workflow's triggers are `push`/`workflow_run` only, so
  it is safe; pg_regress (which has a PR trigger) must keep its PR leg on
  `ubuntu-latest` when it migrates (doc-026 §2, a later phase).

## Consequence you must respect: raw ssh, not Docker actions

Because there is **no docker socket**, a Docker-based marketplace action (our
current `appleboy/ssh-action@v1.2.0`, which is a container action) **cannot run on
this runner**. Every migrated SSH job must use a raw `ssh` run step (that is why the
image installs `openssh-client`). The proposed notify workflow shows the exact
conversion. Host, user, key, and script stay semantically identical to today.

## Phase 2 — bring the runner up on niue (server-side, root; NOT done here)

Step by step, for whoever runs it (the King, per the no-manual-writes rule this is
a human action):

1. **Create the dedicated user** (sibling of the slot homes, NOT under any slot or
   devops): `useradd -m -s /bin/bash github-runner && usermod -aG docker github-runner`
   (docker group, **no sudo**).
2. **Copy the repo artifacts** to `/home/github-runner/`:
   `Dockerfile`, `entrypoint.sh`, `docker-compose.yml`, `.env.example`
   (chown `github-runner:github-runner`).
3. **Mint the 1-hour registration token and write `.env`** (do this right before
   step 4 — the token expires in an hour):
   ```
   gh api -X POST repos/statisticsnorway/statbus/actions/runners/registration-token --jq .token
   ```
   Put it in `/home/github-runner/.env` as `RUNNER_TOKEN=…`.
4. **Build + start** (as github-runner): `cd /home/github-runner && docker compose up -d --build`.
   Confirm: `docker logs gha-runner` shows registration; GitHub → repo → Settings →
   Actions → Runners shows **niue** online with labels `self-hosted, niue`. Blank
   `RUNNER_TOKEN` in `.env` afterwards.
5. **Whitelist the docker bridge in CrowdSec** so a key mishap can never self-ban the
   runner (this is the private RFC1918 bridge subnet — categorically NOT whitelisting
   GitHub's public ranges, which the King rejected). Determine the bridge subnet
   (`docker network inspect gha-runner_default`) and add it to the crowdsec whitelist.
6. **Install the weekly refresh:** copy `upgrade-to-latest-gha-runner.sh` →
   `/usr/local/bin/` (chmod +x), the `.service`/`.timer` → `/etc/systemd/system/`, then
   `systemctl daemon-reload && systemctl enable --now gha-runner-upgrade.timer`.
7. **Observe one day idle** (doc-026 §3 step 1) — registered, labeled, receiving
   nothing — including one weekly-timer pass, before any workflow migrates.

## Phase 3 — migrate the notify canary (after the runner is proven online)

Replace `.github/workflows/notify-all-clouds.yaml` with the PROPOSED file here (once
its two open questions below are ruled), which moves the notify legs to
`[self-hosted, niue]`, converts to raw ssh, and adds the hosted `runner-online`
canary. Then pg_regress's trusted legs, then the slot deploys — each doc-026 §3.

## Rollback (every step)

One line per workflow: revert `runs-on:` back to `ubuntu-latest`. The hosted path
keeps existing the whole time (modulo the original intermittent bans). To retire the
runner entirely: `docker compose down` on the box + remove it from the GitHub Runners
UI + disable the timer.

## Open questions carried to the architect (see the proposed workflow's header)

- **A — raw-ssh host-key policy** (accept-new pinned in the work volume vs a
  pre-seeded known_hosts).
- **B — canary auth**: listing runners needs repo *administration* permission, which
  `GITHUB_TOKEN` cannot be granted; the canary as written needs a read-scoped PAT
  secret (`RUNNER_STATUS_TOKEN`), which is a standing (GitHub-side, read-only)
  credential — in tension with doc-026 delta 1's "no durable secret." Rule: accept the
  read-only status PAT, or choose another liveness signal.
