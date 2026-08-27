---
id: STATBUS-268
title: >-
  install-ukraine: new cloud installation for Ukraine on niue, following the
  established multi-tenant pattern
status: To Do
assignee: []
created_date: '2026-08-27 12:56'
updated_date: '2026-08-27 16:13'
labels:
  - ops
  - cloud
  - installation
dependencies: []
priority: high
type: feature
ordinal: 261000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
The King (2026-08-27): multiple countries are waiting eagerly for new installations; Ukraine is first, to be installed on niue following the established cloud installation pattern (doc/CLOUD.md, ops/create-new-statbus-installation.sh — slot code, port offset, subdomain, per-slot Linux user, database, cookie names per the deployment-slots scheme).

Execution notes to settle with the architect at planning:
- Slot code (presumably `ua`) and port offset — offset 2 is recorded as reserved-for-future-use on niue since Norway's migration to rune (doc/CLOUD.md:37); confirm whether it is reusable or a fresh offset is cleaner.
- This is the FIRST new slot since the recent doctrine landings, so it exercises them: the box's channel comes from UPGRADE_ROLE (STATBUS-254 durable mechanism — an ordinary installation is production/stable, declared explicitly); any CI door grants for the new slot are a reviewed commit to ops/niue/sshdoers + a Stage 8 re-run (STATBUS-259 — never a hand-edit of /etc/sshdoers).
- The installation must land on a NAMED release (canonical-commit-naming), and the box then follows its channel.
- Remaining countries: names pending from the King — each gets its own ticket on this pattern.

WHAT IS ACHIEVED: Ukraine's statistical office has a running StatBus on niue, installed entirely through the established pattern with zero hand-managed state, and the path is warm for the countries behind it.
<!-- SECTION:DESCRIPTION:END -->

## Comments

<!-- COMMENTS:BEGIN -->
author: architect
created: 2026-08-27 13:05
---
EXECUTION SPEC, part 1 of 2 — identity, release, role. Since more countries follow, every choice is made as a TEMPLATE decision rather than a one-off.

## 1. SLOT IDENTITY — `ua`, offset **10**, with one precondition

The runbook already answers it: *"Next available offset is 10 for new deployments"* (doc/CLOUD.md:337). Offset 2 stays reserved.

**I considered taking the reserved offset 2 and rejected it.** Its stated purpose — *kept for rollback if `no` ever needs to come back to niue* — is arguably stale, since Norway is now deliberately standalone AND the human canary, and returning it to niue would undo a ratified topology. But **a reservation should be released deliberately, on its own merits, not consumed opportunistically by the next thing that needs a number.**

**PRECONDITION, and it is why offset 10 is the better choice rather than merely the documented one: `ua` would be the FIRST TWO-DIGIT PORT OFFSET.** Ports compute as `3000 + offset×10` → 3100-3106. I found no single-digit assumption in `cli/internal/config/config.go` (:353 generates it as a string, used arithmetically), **but I audited one file, not every consumer** — Caddy templates, container naming and the docs all touch it.

**Audit those before committing.** And note this argues FOR 10, not against it: we reach two-digit offsets eventually, and it is far better to meet that on a box we are deliberately building than accidentally later with several more slots depending on it. Taking offset 2 would defer a problem we already have.

*Fallback if the audit finds a real assumption:* fix it (preferred), or fall back to offset 2 with the reservation **formally released and recorded** — never silently consumed.

## 2. WHAT IT INSTALLS — the CURRENT STABLE, re-derived at install time

The current **stable release**, named per canonical-commit-naming. **Do not take the version from this comment** — re-derive it at execution time (newest `v*` tag without `-rc.`), because a version named in a design ages, and this spec will be read months from now by whoever installs the next country.

Doctrine-correct for a second reason too: installing the current stable and upgrading when the next is promoted **is exactly the customer path** — the same fidelity argument the King made ruling STATBUS-250's reset target.

## 3. ROLE AND CHANNEL — `production` / `stable`

Ukraine is an ordinary NSO installation: **stable channel, offered each promoted release, a human performs the upgrade** (the King's opt-in amendment to STATBUS-248). It is not a canary and must never be described as one.

Declare it through whichever mechanism is live at execution time — `UPGRADE_ROLE=production` if STATBUS-254's derive-mechanism has landed, otherwise `UPGRADE_CHANNEL=stable` via STATBUS-251's path. **Verify which is live rather than assuming; both are in flight.**
---

author: architect
created: 2026-08-27 13:05
---
EXECUTION SPEC, part 2 of 2 — inbound access, ownership, and what makes this a template.

## 4. INBOUND ACCESS — **NONE on day one.** This is the spec's most important line.

Ukraine needs **zero sshdoers entries** to start, and I checked each candidate rather than assuming:

- **no `apply-latest`** — nothing pushes to it, and it is opt-in human;
- **no `ci-deploy-status`** — it has no deploy workflow, because STATBUS-251 stopped generating them;
- **no `ci-notify`** — `notify-all-clouds.yaml` carries an explicit slot matrix (:102-108) which simply does not list `ua`.

So the box starts with **no inbound grants at all** — the correct posture for an installation nobody drives remotely, and the first slot in our history to start that way.

**If someone later wants Ukraine in the notification fan-out**, that is a reviewed commit adding `ua` to the matrix AND a `ci-notify` entry to `ops/niue/sshdoers`, plus a Stage 8 re-run. **That is the STATBUS-259 payoff arriving exactly on schedule**: adding a grant is now cheap, reviewed and provable — so there is no reason whatsoever to pre-grant access "in case", which is how every allowlist in history has grown.

**TEMPLATE RULE: a new slot starts with zero inbound access. Every grant is added afterwards, one at a time, each with a stated reason.**

## 5. STEPS AND OWNERSHIP

**Repo-side (MECHANIC): nothing is required on day one.** `ops/create-new-statbus-installation.sh` no longer generates per-slot workflows (STATBUS-251), so there is no file to add — which is itself worth noticing, since it is the first install where that is true. If the offset audit finds an assumption, that fix is mechanic work and **lands first**.

**On niue (OPERATOR), with a pre-declared command list** per the King's standing directive: DNS verification → the creation script with `ua` and the resolved offset → settings and channel confirmation → services up and users created.

**ACCEPTANCE: verify from the RUNNING SERVICE, never the file.** The box's own `Upgrade service started (channel=stable, …)` line is the evidence. A `grep` of `.env.config` is not proof — the fleet correction established exactly this, and it is the same daemon-caches-at-startup mechanism here.

## 6. WHAT MAKES THIS A TEMPLATE

Three decisions generalise to every country behind Ukraine:

1. **Zero inbound access on day one**, grants added individually with reasons.
2. **The current stable, re-derived at install time** rather than a version named in a document.
3. **Production role, opt-in human upgrades** — an ordinary installation, never a canary.

The only per-country variables are the **slot code, the port offset, and the domain**. If a future country needs anything else, that is a signal the template is wrong rather than that the country is special — and it should come back here rather than being handled locally.
---

author: mechanic (pinned by foreman)
created: 2026-08-27 13:38
---
OFFSET-10 AUDIT COMPLETE — the spec's precondition is DISCHARGED: eleven consumer sites, every one SAFE, zero UNSURE. The load-bearing findings: only TWO arithmetic sites exist repo-wide (config.go:358,514 — plain Go int `basePort + offset*10`, no fixed-width formatting downstream); every other consumer (caddy templates, compose files, app naming) takes config.go's OUTPUT as an opaque string — the shape immune to digit-count bugs. ops/create-new-statbus-installation.sh:317-318 picks the next offset with an any-length sed capture and explicit `sort -n` (numeric — correctly orders 10 after 9). Container/DB/cookie naming keyed on slot CODE, zero offset dependency. Hardcoded offsets in dev.sh (9, local sandbox) and test fixtures (1) are N/A to provisioning.

One flagged doc gap, not a bug: doc/CLOUD.md's Current Deployments table gains the ua/offset-10 row when the slot exists — belongs to the install execution, not this audit.

UKRAINE'S REMAINING GATE: a stable release to install (the rc.10 → canary → stable sequence, STATBUS-271). Everything else — DNS (done), spec (ruled), offset (audited) — is ready.
---

author: architect (pinned by foreman)
created: 2026-08-27 13:39
---
OFFSET 10 COMMITTED for Ukraine — and the clearance is recorded as a PERMANENT PROPERTY, not a one-time check: OFFSET WIDTH IS UNCONSTRAINED (audited eleven consumers, 2026-08-27). The structural reason — only two arithmetic sites, plain ints, no fixed-width formatting, all other consumers take pre-formatted output — clears ANY width, 100+ included. The next country's spec must NOT repeat this audit; cite this comment instead.

The finding the architect singles out: the next-offset picker's NUMERIC sort (create-new-statbus-installation.sh:317-318). A lexical sort would put "10" before "9", report 9 as the max, hand 10 to a SECOND slot, and collide with Ukraine — both boxes looking correctly configured until the ports clashed. Verified numeric, not assumed.
---

author: architect (pinned by foreman)
created: 2026-08-27 16:13
---
KING'S AMENDMENT (2026-08-27, before leaving for the evening): install NOW from v2026.08.0-rc.10 rather than waiting for stable — approved explicitly, operator executing with the users-step pause reserved for the King's return.

ARCHITECT'S VERIFICATION of the amendment's one silent hazard: does an rc-installed box declaring stable end up STRANDED (supersedeBelowInstalled retiring everything its channel offers)? NO — CalVer ordering treats a release as newer than a prerelease of the same version (service.go:4499), so the eventually-promoted stable always outranks the rc; discovery offers it and a human opts in. Channel-following from an rc install is verified, not assumed — the failure mode would have been a silently-never-upgraded statistical office.

ACCEPTED RISK, recorded as a decision: until a stable exists, Ukraine runs code not yet promoted — and if the rc.10 chain goes red, Ukraine is live on a candidate we declined to bless. The King's call, defensible (a working install now beats a delayed one); remedy is the ordinary path — the box is offered the eventual stable and a human takes it.
---
<!-- COMMENTS:END -->
