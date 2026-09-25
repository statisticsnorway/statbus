---
id: STATBUS-361
title: >-
  One location for SSB-shared operator credentials: GITHUB_TOKEN first, in
  .env.credentials, reachable by the fleet script over SSH; SOPS deferred with
  named triggers
status: In Progress
assignee: []
created_date: '2026-09-07 13:48'
updated_date: '2026-09-25 20:58'
labels:
  - release-bug
  - ops
  - security
  - fleet
dependencies:
  - STATBUS-357
ordinal: 60
---

## Merge status 2026-09-25 (coordinator)

Merged to master at c05b3ccf6 (branch fix/361-credentials-rebased, c514d4264) after a coordinator rebase (the original branch was based on an old master and reverted unrelated work) and two review rounds. Post-merge fixes: errcheck in the loader test (3cf30b234); SEQ_API_KEY placeholder restored into .env.credentials because docker-compose.app.yml declares it :?-required (1e98c8ace + regression test). Still open: live-deployment evidence (authenticated dev calls; Norway/demo stay anonymous) — the ticket stays open for that.

## Implementation 2026-09-25, review B correction

Rebased onto current `origin/master` without conflicts, retaining master's password-prompt changes. Installer credential and settings steps now migrate legacy token placement only when a previously generated `.env` identifies a rerun. Fresh installs with an authored secret refuse plainly without moving it. Standalone config generation on an existing box refuses with `./sb install` as the migration path. Operator-path fixture tests exercise both installer steps on fresh state, duplicate-line migration and idempotent reruns, and standalone legacy guidance. No Docker or live deployment was run. Fleet credential installation and authenticated-call evidence remain outstanding, so this ticket remains In Progress.

## Implementation 2026-09-25

Review C remediation: installer reruns migrate legacy operator tokens from `.env.config` into `.env.credentials` before config-file validation, retaining an already-present credential as authoritative and making repeat runs no-ops. The new-installation provisioner writes shared tokens to `.env.credentials`. This is local code validation only, not evidence of a token installed on dev or authenticated GitHub calls. Fleet acceptance remains pending.

Follow-up review correction: migration is now scoped to the install command's credential/config steps, not ordinary `sb config generate`; the latter rejects a newly misplaced secret without moving it. Migration deletes every duplicate assignment of a legacy secret, not merely its last occurrence. Local tests exercise fresh rejection, duplicate-line removal, and idempotence. Live fleet acceptance is still pending.

Scratch branch `fix/credentials-361` moves optional tokens to `.env.credentials`, rejects `GITHUB_TOKEN`, `SLACK_TOKEN`, and `SEQ_API_KEY` in `.env.config`, and reads the GitHub token for the upgrade service without copying it into generated `.env`. Fixture tests cover refusal and the token's documented home. Acceptance remains pending: the operator must move existing dev values, install the fine-grained token personally, observe authenticated dev calls at 5000/h, and confirm Norway/demo stay anonymous. No remote credential changes or fleet verification were performed.

## Status 2026-09-24

**To Do:** acceptance 1-4 not met: no `.env.config` secret rejection or dev token installation is evidenced (`4a0ff7f34` ticket history). **Remaining:** enforce `.env.credentials` storage, reject config-file secrets, run token-backed tests, and verify authenticated dev calls while demo/Norway remain intentionally anonymous.

Baseline: `origin/master` at `373d15fc3`. Criterion disposition and remaining positive targets are above; the acceptance criteria below remain authoritative. An authored but unrun VM scenario is **proof pending**, not met.

## Ruling (owner, 2026-09-07)

Discussed SOPS+age (the Brovs/DevOps pattern: `.sops.yaml` recipients =
deploy key held as a CI secret + the owner's SSH-derived rescue identity +
daily identity; `secrets/<slot>.enc.yaml` committed to the public repo).
Ruled: **not yet**. StatBus secrets are almost all per-box, generated in
place by `install.sh`, and governed by SSH access; the SSB-shared set is a
handful of values that change rarely. What is needed now is only a
LOCATION for those values and support for reading it, not an encryption
layer. The first value is the `GITHUB_TOKEN` for `dev` (STATBUS-341: dev is
the tokened box, `no` and `demo` are anonymous sentinels).

## Ground truth (2026-09-07)

| value | today | belongs |
|---|---|---|
| per-box DB passwords, JWT secret, service role key | `.env.credentials` on the box, generated once | stays; never leaves the box |
| `SLACK_TOKEN` | `.env.config` AND `.env.credentials` on dev (both) | `.env.credentials` only |
| `SEQ_API_KEY` | `.env.config` on dev | `.env.credentials` |
| `HCLOUD_TOKEN` | `.env.credentials` on the owner's laptop; GitHub secret for the orchestrator | as is |
| `GITHUB_TOKEN` (341) | documented as a `.env.config` opt-in entry | `.env.credentials` (it is a credential) |
| `secrets.GITHUB_TOKEN` in CI | GitHub-issued per run | as is |

The rule that falls out: **`.env.config` holds no secrets; every token,
password, or key lives in `.env.credentials`** (mode 0600, untracked,
creation-header documented, never auto-propagated). Two values on dev
violate it today.

## Work

1. Move `GITHUB_TOKEN`'s documented home from `.env.config` to
   `.env.credentials`: `config.go` reads it from there (env still wins), the
   creation header of `.env.credentials` documents it commented-out, and
   `.env.config`'s header no longer mentions it. Tests from 341 updated.
2. Same for `SLACK_TOKEN` and `SEQ_API_KEY`: readers accept
   `.env.credentials`; `./sb config generate` refuses (with a directive
   message) when a known secret name is found in `.env.config`, so the two
   dev violations are fixed by the operator moving the lines, not silently.
3. `cloud.sh` never holds secrets itself; when a verb needs one for a box
   it reads that box's `.env.credentials` over SSH (SSH is the trust
   boundary, as today). No copy of any box's secret ever lands on the laptop
   or in chat.
4. Owner installs dev's fine-grained read-only `GITHUB_TOKEN` into dev's
   `.env.credentials` by hand (one line, once). Not done by any agent.
5. Doc: one paragraph in `doc/CLOUD.md` "Where credentials live" with the
   table above.

## Deferred: SOPS+age (trigger conditions, so the reasoning is not lost)

Adopt the Brovs pattern (deploy age key as a GitHub Actions secret, owner's
SSH-derived rescue identity, `secrets/*.enc.yaml`) when ANY of these holds:

- more than one SSB box needs a non-generated secret installed (today: one,
  dev's token), or
- STATBUS-358's approval service carries its own credentials that must be
  provisioned from the repo, or
- a second person needs to run the paid harness or operate the fleet
  regularly and the "copy-paste through chat" path recurs.

Until then the cost (a tool, a recipient list to re-key, a deploy key to
protect) exceeds the benefit for a handful of values.

## Acceptance

1. `grep -E '^(GITHUB_TOKEN|SLACK_TOKEN|SEQ_API_KEY)=' .env.config` on dev
   returns nothing; the same names in `.env.credentials` work.
2. `./sb config generate` on a fixture with a secret in `.env.config` exits
   non-zero naming the key and the file it belongs in.
3. 341's tests pass with the token read from `.env.credentials`.
4. dev's upgrade service logs authenticated GitHub calls (rate-limit header
   shows 5000/h) after step 4; `no` and `demo` remain anonymous per
   `./cloud.sh status`.

## Batch sequencing (owner ruling 2026-09-15)

This ticket lands in the ONE batch after the current release: it does not
touch master until v2026.09.1-rc.08 (or the first later rc that goes fully
green) has been installed on Norway and promoted to stable. Then all batch
tickets land in one push, one candidate, one ladder. Position in that push:
**6 of 8**. secrets in .env.credentials; no open ruling; build in scratch once the owner says go

Batch order: 370 -> 368 -> 367 -> 363 -> 357 -> 361 -> 362 -> 359.

## Reconciliation 2026-09-23

Classification: PARTIAL. Evidence: post-release scratch batch only; credential relocation and fleet proof remain.

Remaining: Land secret-file enforcement and prove authenticated dev calls while demo/Norway remain intentionally anonymous.

## Notes 2026-09-25

The upgrade service loads optional `GITHUB_TOKEN`, `SLACK_TOKEN`, and `SEQ_API_KEY` from `.env.credentials` at startup, before API requests, git fetches, or callback subprocesses. A nonempty process environment value wins over the credentials file. The user-level systemd unit does not source the file, avoiding systemd EnvironmentFile precedence over an explicit process environment. `GITHUB_TOKEN` reaches both GitHub API requests and the authenticated git-fetch header; `SLACK_TOKEN` reaches the callback subprocess. Generated `.env` continues to supply `SEQ_API_KEY` to app/worker containers. No token value is logged by the loader. Deployment observation for dev authentication and anonymous Norway/demo remains pending.
