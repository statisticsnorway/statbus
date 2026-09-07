---
id: STATBUS-361
title: >-
  One location for SSB-shared operator credentials: GITHUB_TOKEN first, in .env.credentials, reachable by the fleet script over SSH; SOPS deferred with named triggers
status: To Do
assignee: []
created_date: '2026-09-07 13:48'
updated_date: '2026-09-07 13:48'
labels:
  - ops
  - security
  - fleet
dependencies:
  - STATBUS-341
---

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
