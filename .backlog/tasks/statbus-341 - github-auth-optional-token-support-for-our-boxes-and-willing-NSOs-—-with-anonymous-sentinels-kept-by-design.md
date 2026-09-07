---
id: STATBUS-341
title: >-
  github-auth-optional: token support for our boxes and willing NSOs — with
  anonymous sentinels kept by design
status: To Do
assignee: []
created_date: '2026-09-02 12:21'
updated_date: '2026-09-07 14:02'
labels:
  - ops
  - upgrade
  - resilience
dependencies: []
priority: medium
type: enhancement
ordinal: 334000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
GitHub-transient incidents (rune rc.02 preswap fetch; dev notify git fetch --tags, same day, same signature: anonymous smart-HTTP answering an auth challenge) motivate OPTIONAL authenticated HTTPS — with a deliberate limit the King set: we must keep living the anonymous path our customers cannot escape.

Design for ruling before build:
1. HTTPS stays the transport (SSH needs a key; customers have none). Anonymous stays the product default and the tested norm.
2. Optional token support: a documented .env.config entry (entry-way file discipline — creation-header documentation, never auto-propagated) that, when present, authenticates git fetch + REST calls (5000/h vs 60/h; no anonymous auth-challenge). Usable by us or by any NSO with its own credential. Read-only fine-grained token, repo-scoped.
3. NO-MONOCULTURE REQUIREMENT (the King, 2026-09-02): some of our own boxes MUST stay anonymous by design so we know the tokenless path works — the sentinels. Proposed split: canaries (dev, rune) stay anonymous — their role is to hit what customers hit; stable production slots may take the token. The split is recorded per box and verifiable (cloud.sh status could show it).
4. Primary defense remains STATBUS-338's resilience (local-objects fast path, bounded retry) — the token is comfort, not correctness.
5. Small companion: give discovery/notify ticks the same bounded transient retry preswap got (today a Notify job reds on one blip; a retry makes it a non-event). May land independently of the token.

Acceptance (post-ruling): token entry documented at its point of entry; fetch/REST paths use it when present; at least dev + rune verified running anonymous (the sentinel list is explicit, not accidental); discovery/notify retry landed; a tokenless box behaves identically to today.
<!-- SECTION:DESCRIPTION:END -->

## Comments

<!-- COMMENTS:BEGIN -->
author: foreman
created: 2026-09-03 13:15
---
KING'S RULING (2026-09-03), design amended and APPROVED for this build wave — supersedes the description's proposed split:

1. ONE NAME: GITHUB_TOKEN everywhere — the product already reads it for REST (github.go:144), workflows already export it. The .env.config entry uses the same name (entry-way documented, never auto-propagated); env wins over file. The release gate's anonymous deployability probes KEEP ignoring it by design (check.go:302 — the principled carve-out).
2. PURE ACCELERANT PRINCIPLE: token present → authenticated fetch+REST; absent → byte-identical to today. No forks, no migration, add/remove any time.
3. FLEET SPLIT (reverses the old proposal — sentinel = customer-fidelity ROLE, not the high-frequency boxes): dev TOKEN (5-min ticks, orchestrator-driven — this week's real victim), demo TOKEN (automated channel-follower), Norway ANONYMOUS SENTINEL (human canary lives the customer path; manual, 6h, low volume), country slots (et/jo/ma/ug) ANONYMOUS (King: low-frequency is fine anonymous).
4. HARNESS SPLIT: the two happy smokes STAY ANONYMOUS (they ARE the customer-experience test — sentinel duty); the wedge/recovery ARCS get the token (workflow GITHUB_TOKEN into the VM env) — they test recovery machinery, and anonymous 401 noise there is pure false-red (proven: 3 arc reds 2026-09-03 were storm-perturbed recovery-boot trajectories, zero arc defects).
5. Kept: read-only fine-grained repo-scoped token; 338 retry resilience remains primary defense; discovery/notify bounded-retry companion lands with this; sentinel list explicit + visible in cloud.sh status.

Context for urgency: 36h of GitHub 401-challenges on anonymous git-over-HTTPS from Hetzner IP space (authenticated paths: zero failures in the same windows) cost ~7 RC iterations and 3 arc false-reds. Queued alongside 344 for the post-promotion wave.
---
<!-- COMMENTS:END -->

## Ruling (owner, 2026-09-07): sentinels are the manually driven boxes

Ground truth first (doc/upgrades.md, config.go): the upgrade service on
every box polls GitHub on `UPGRADE_CHECK_INTERVAL`, DISCOVERS releases on its
channel into `public.upgrade` as `available`, and pre-pulls images
(`UPGRADE_AUTO_DOWNLOAD`, default true, images only). It never schedules by
itself; scheduling is a human act (admin UI or `./sb upgrade schedule`). The
automatic scheduler (`edge`) was retired 2026-08-19. `dev` is automated only
because `deploy-to-dev.yaml` schedules the candidate from outside.

The split follows HOW a box is driven:

| box | driven | GitHub auth | why |
|---|---|---|---|
| `no` (Norway, rune) | manually: a person installs each candidate | **anonymous sentinel** | lives the customer path at customer volume |
| `demo` | manually: `stable`, no external scheduler | **anonymous sentinel** | same |
| `dev` | automatically: orchestrator canary schedules every candidate; 5-min ticks | **token** | the real victim of the anonymous limit |
| `et`, `jo`, `ma`, `ug`, other country slots | manually, low frequency | anonymous; a token is an allowed `.env.config` entry, never installed by us on a customer-shaped box | low volume is fine anonymous |
| harness happy proofs (`install-works`, `upgrade-works`) | anonymous | they ARE the customer-experience test |
| harness recovery proofs | token from the workflow | anonymous 401 noise there is pure false red |

The sentinel set is DATA in the fleet registry (`cloud.sh`), shown by
`./cloud.sh status` as `auth: anon|token`, and a test asserts `no` and
`demo` are in the anonymous set and `dev` is not.

## Evidence (2026-09-07, HEAD d7714827a)

| acceptance | evidence |
|---|---|
| retry on rate-limit answers, bounded | `1c33ec1b1`; TestGithubDoRetriesRateLimitThenSucceeds_STATBUS341, TestGitRateLimitFailureClassification_STATBUS341; Luna: forever-403 bounded at 3; real 401 and network timeout one attempt each |
| one `GITHUB_TOKEN` entry, REST + git fetch (env, never argv), env wins, byte-identical when unset | `9ce68240c`, `cf6e30c6f` (discovery fetch too; generate does not auto-insert; HTTP-date Retry-After); `23bb33885` (past date = retry now); TestGithubRequestAuthorizationIsOptional_STATBUS341, TestGitFetchEnvironmentAuthorizationIsOptional_STATBUS341, TestGithubRetryDelayPastHTTPDateIsZero_STATBUS341 |
| sentinels as data, visible, pinned by test | `cd43deb92`: registry fifth field `anon|token`; `./cloud.sh status` AUTH column; `no`, `demo`, country slots anon; `dev` token; test fails if `no`/`demo` become token or `dev` anon. Live read-only `status prerelease`: dev token, no anon |
| harness split | recovery arcs get `secrets.GITHUB_TOKEN` (GitHub's per-run token, not a PAT); happy proofs anonymous; VM token file 0600 from creation, appended last inside the guarded transfer block so no failure path leaks it (`6b77ab021`, `d7714827a`, probe `tmp/probe-341-errexit-cleanup.sh`) |
| no token installed anywhere | none; dev's token is the owner's one-line manual step, tracked in STATBUS-361 |
| review trail | `tmp/STATBUS-341-review/REPORT.md`: Luna r1 REJECT (2 HIGH, 1 MED, 1 LOW), r2 REJECT (2 LOW), r3 REJECT (1 LOW), r4 REJECT (1 LOW), r5 ACCEPT at d7714827a |
| CI at HEAD | Fast Tests, app build, Images green; Go Test's golangci-lint red on findings owned by the concurrent 354 work (unchecked `d.rollback` returns) plus two `Body.Close` in github_test.go; fix in flight (llama). Done is recorded when that job is green. |

## Coordination checkpoint: 2026-09-07 16:31

Implementation and independent review evidence already recorded. At `f2862bd47`, runner Fast Tests, Go Test, app build/lint and Images succeeded. Twin commit `6e421c2f0` not yet published at this check. Await exact new HEAD CI before Done.
