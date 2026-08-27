---
id: STATBUS-283
title: >-
  creation-script-binary-gap: the slot-creation script clones and checks out but
  never procures the sb binary — its tail should delegate to install.sh
status: To Do
assignee: []
created_date: '2026-08-27 16:47'
updated_date: '2026-08-27 19:42'
labels:
  - ops
  - cloud
dependencies: []
priority: high
type: bug
ordinal: 276000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Found on Ukraine's maiden run (2026-08-27): ops/create-new-statbus-installation.sh clones the repo and (since the version pin) checks out the named tag, then assumes ./sb exists (config generate at ~:294/:440, users create, start) — but sb is gitignored and the script never procures it. Every existing slot predates this path; Ukraine hit the gap live.

The product already owns binary procurement: install.sh places ~/statbus/sb from the commit-tagged ghcr.io/statisticsnorway/statbus-sb image (docker pull → create → cp, no toolchain, install.sh:148-166) and then ./sb install does config/docker/DB/service. The immediate Ukraine resume used exactly that path.

Durable fix (Lego principle — reuse, don't duplicate): the creation script's tail (everything after user/ssh/DNS setup) delegates to install.sh with the named version instead of hand-running clone/checkout/config/start — one procurement mechanism, one owner. Design for the architect: which steps remain creation-specific (slot user, authorized_keys, deployment key, ACLs, offset selection) vs which delegate; the version argument threads through.

WHAT IS ACHIEVED: a new slot is provisioned by the same mechanism every installation uses, and the binary can never be missing on a maiden run again.
<!-- SECTION:DESCRIPTION:END -->

## Comments

<!-- COMMENTS:BEGIN -->
author: foreman
created: 2026-08-27 17:00
---
EVIDENCE from the Ukraine maiden run (2026-08-27), in scope for this consolidation: after ops/create-new-statbus-installation.sh completed, https://ua.statbus.org did NOT serve — niue's HOST Caddy had the new slot's ACL/route wired on disk but the running process had never loaded it. The fix was a pre-declared root action: caddy validate, then reload, and only then did the front door answer. The script wires the config but never reloads the host router; the next country hits the same dark front door unless this lands. Consolidation shape stays as ticketed (creation tail delegates to install.sh); the host-reload step belongs in the root-side portion with validate-before-reload preserved.
---

author: architect
created: 2026-08-27 19:41
---
**RULING part 1 of 2: the criterion and the step-split.**

## The criterion, so future steps sort themselves

The split is not "setup vs product". It is **who owns the fact**, and it has a mechanical test:

> **If a second `./sb install` on the same box must REDO it, it belongs to install. If a second run must NOT touch it, it belongs to creation.**

A fact the HOST owns — which unix user exists, which port offset is free, which keys may log in, what the root-owned proxy trusts — cannot be written by a product that runs unprivileged as one slot among ten. A fact the INSTALLATION owns — its binary, its generated config, its containers, its schema, its users — must be written by the product, because the product is what re-derives it on **every upgrade for the rest of the box's life**. Anything creation writes that install also writes is a second source of truth that will drift.

## Stays in the creation script (host-owned, runs exactly once)

| Step | Site | Why it cannot move |
|---|---|---|
| Slot user + home | root section | identity; predates the product |
| `authorized_keys` / operator access | root | identity |
| GitHub deployment key | `:447-453` | identity |
| Offset + slot code/name/mode + `UPGRADE_ROLE` | `:370-426` | **allocation decisions** — the offset is a fact about the other nine slots; the product cannot know it is free |
| `STATBUS_URL` / `BROWSER_REST_URL` | `:428-444` | host DNS fact |
| Secrets lifted from `statbus_dev` | `:455-472` | cross-slot read, requiring host knowledge the slot user must not have generally |
| Caddy ACLs (`setfacl`) | `:487-502` | root-only, persists |
| **Host Caddy validate + reload** | **MISSING** | root-only; part 2 |

## Delegates to `./sb install` at the named version

| Step | Currently | After |
|---|---|---|
| Binary procurement | ad-hoc | install, at the pinned version |
| `./sb config generate` | `:482` | inside install |
| `./sb start all` | `:511` | inside install |
| DB creation | `:514` **`./dev.sh create-db`** | inside install, gated by the probe ladder |
| `./sb users create` | `:515` | inside install |
| `source /etc/profile.d/homebrew.sh` | `:513` | **deleted** — a build-time dependency has no business in provisioning once a versioned binary is procured |

## The delegation fixes a live destructive bug — lead the ticket with this

`:514` calls **`./dev.sh create-db`, unconditionally**. Two defects in one line:

1. **Destructive and ungated.** AGENTS.md marks `create-db` DESTRUCTIVE, LOCAL DEVELOPMENT ONLY — it drops and recreates. **Re-running the creation script against an existing slot would destroy that country's data.** The script is otherwise carefully idempotent (every setting is compare-then-write), which makes this line *more* dangerous, not less: the surrounding care reads as a promise that re-running is safe.
2. **A dev script in production provisioning**, contrary to AGENTS.md's own definition of `./dev.sh`.

`./sb install` is the right replacement precisely because **its 9-state probe ladder decides**: `fresh` sets up, `nothing-scheduled` is an idempotent refresh. The delegation is not tidying — **it converts a re-run from data loss into a no-op.** That is the strongest argument for this ticket and belongs in its headline.
---

author: architect
created: 2026-08-27 19:42
---
**RULING part 2 of 2: the missing Caddy step, ordering, and one item the mechanic must NOT touch.**

## The missing step — and why `validate` is not politeness

The script generates the slot caddyfile (`:482`) and grants the proxy read access (`:493-500`), then **never tells the host Caddy to load it**. Ukraine came up correct and unreachable — comment #1's evidence.

Add as the LAST root-side step, after install returns:

```
ssh root@$HOST bash <<'RELOAD_CADDY'
    caddy validate --config /etc/caddy/Caddyfile || {
        echo "REFUSING TO RELOAD: host Caddy config is invalid with the new slot." >&2
        echo "The other slots are still served by the running process. Fix the" >&2
        echo "slot caddyfile, then re-run this script." >&2
        exit 1
    }
    systemctl reload caddy
RELOAD_CADDY
```

**Validate is blast-radius containment on a multi-tenant box.** One malformed new-slot caddyfile, reloaded unvalidated, takes the proxy down for **all ten countries**. Validate-then-reload bounds the worst case to "the new slot is unreachable" — which is exactly today's state, so the step cannot make things worse and can prevent a fleet outage.

**And the failure must be fatal, not a warning.** An unreachable new slot that exits 0 is discovered by the country, not by us. That is precisely how Ukraine's gap surfaced.

## Ordering, and the one dependency that is easy to get backwards

> settings → `./sb install <version>` → ACLs → **validate** → **reload**

**ACLs must precede validate.** Caddy reads the file as the `caddy` user; a validate run before `setfacl` can fail on permissions and report a perfectly good config as broken — sending whoever hits it hunting a syntax error that does not exist.

## Not in this ticket — flagging so it is not folded in

`:438-444` writes `BROWSER_REST_URL` with compare-then-write, but `dotenv.Generate` is **first-writer-wins** (`cli/internal/config/dotenv.go:223-225`): it returns an existing value and writes only on a miss. So on a box where the key already exists, **`./sb config generate` cannot correct it** — the creation script's write is the only thing that can, which is an argument for that write staying creation-side, and a separate argument that the generate path is weaker than it looks.

That is the already-filed follow-up. **It is a behaviour change and must not ride this ticket**, which is mechanical. Named here only so the mechanic recognises it as deliberate scope, not an oversight.
---

author: foreman
created: 2026-08-27 19:42
---
PRIORITY RAISED to HIGH on the architect's design finding: ops/create-new-statbus-installation.sh:514 runs `./dev.sh create-db` UNCONDITIONALLY — destructive, ungated, a dev-only script in production provisioning. Re-running the creation script against an existing slot DESTROYS that country's data, and the script's meticulous idempotence everywhere else reads as a promise that re-running is safe. The delegation to ./sb install fixes this BY CONSTRUCTION (the probe ladder decides; a re-run becomes a no-op instead of data loss) — that is now the ticket's lead argument, with the binary gap and host-Caddy reload as the riders. Mechanic executes against the architect's pinned step-split; ordering trap honored (ACLs before validate — caddy reads as the caddy user); validate-then-reload fatal-not-warning; BROWSER_REST_URL first-writer-wins deliberately out of scope as pinned.
---
<!-- COMMENTS:END -->
