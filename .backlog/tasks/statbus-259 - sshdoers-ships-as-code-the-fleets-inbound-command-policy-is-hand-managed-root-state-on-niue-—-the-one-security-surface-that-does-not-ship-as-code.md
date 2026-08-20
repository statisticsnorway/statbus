---
id: STATBUS-259
title: >-
  sshdoers-ships-as-code: the fleet's inbound-command policy is hand-managed
  root state on niue — the one security surface that does not ship as code
status: In Progress
assignee:
  - engineer
created_date: '2026-08-19 20:06'
updated_date: '2026-08-20 06:15'
labels:
  - ops
  - security
dependencies: []
priority: medium
type: chore
ordinal: 252000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
/etc/sshdoers on niue — the byte-pinned allowlist every inbound CI ssh command is checked against — is root-owned, hand-edited host state. The repo carries a copy (ops/niue/sshdoers, whose own header says "Managed by hand"), and nothing syncs or verifies repo↔host: the live policy can drift from the reviewed copy silently, in either direction.

The allowlist SHAPE is correct (least privilege on an inbound credential door). What violates doctrine is the management: every other fix reaches a box through code + the box's own install; the access policy alone reaches it through a person editing a root file over SSH — the exact pattern the fleet-channel correction (STATBUS-254) just removed from configuration.

Surfaced during the King's 2026-08-19 pushback on STATBUS-258 ("an allowlist seems unprincipled"); the architect ruled the diagnosis is precisely this, and that it deserves its own ticket whichever shape 258 takes. Sequencing note: 253/Wave D shrinks this file (deploy entries die with the deploy key); the durable mechanism should land on whatever remains (the notify entrypoints, the pg_regress runner, and any 258 observation door).

WHAT IS ACHIEVED: the live inbound-command policy is provably the reviewed one — drift either fails loudly or is impossible, and the last hand-managed security surface joins the ships-as-code doctrine.
<!-- SECTION:DESCRIPTION:END -->

## Comments

<!-- COMMENTS:BEGIN -->
author: architect
created: 2026-08-19 20:37
---
DESIGN — the mechanism already exists; what is missing is that sshdoers never joined it.

## THE LEGO DECOMPOSITION

**General part, already built and already sanctioned:** `ops/setup-ubuntu-lts-24.sh` — a repo-tracked, staged, root-run host provisioning script with a non-interactive mode, fetched over https and run with sudo. That is *how root state on these hosts is established*, by design and by documented usage.

**Our composition:** the specific commands our CI is permitted to run on each slot.

**What is missing is not a mechanism. It is that sshdoers was never made a stage of the one we have.** `grep sshdo ops/setup-ubuntu-lts-24.sh` returns nothing — the allowlist was established by hand, outside the path built for exactly this, and its own header records the consequence: *"Managed by hand."*

So the fix is not to invent a delivery mechanism. **It is to add a stage that renders `/etc/sshdoers` from `ops/<host>/sshdoers`**, which is already the repo layout (`ops/niue/sshdoers`, with standalone hosts free to carry their own).

## WHY NOT PUT IT IN `./sb`

Because that is the STATBUS-258 error again. A statistical office installing StatBus has no CI door and never will; a `./sb` subcommand for rendering a CI allowlist would put our fleet's arrangement into every installation in the world. **The allowlist is ops territory, not product territory**, and `ops/` is where our fleet's compositions belong. I am stating this explicitly because it is the exact trap I fell into yesterday and the King will be reading for it.

## BOOTSTRAP — there is no new hand-touch

The honest question is whether the mechanism's own installation reintroduces the problem. It does not: **`curl … | sudo ./harden.sh` is already the accepted, documented, one-hand-touch for standing up a host.** Adding a stage to it introduces no new class of manual action — it moves the allowlist *into* the action we already accept, and out of the ad-hoc root session we do not.

The stage must be independently runnable (the script is already staged and non-interactive-capable), so an allowlist change does not require re-running host hardening in full on a live box.

## DRIFT DETECTION — publish a checksum, not the file

The live file must be checkable, but `/etc/sshdoers` is root-owned and its contents are a security policy no slot user should read. Both constraints are satisfied by publishing a hash rather than the content:

- The stage writes `/etc/sshdoers` (root, restrictive) **and** a world-readable `/etc/sshdoers.sha256` beside it.
- Anyone — including an unprivileged slot user over the existing read door — can compare that hash to the hash of the repo copy.

**Where it must fail loudly: the release preflight.** That is the moment the door's correctness actually matters, it is a surface somebody reads every single release, and it already refuses on gate failures. A drifted allowlist means the fleet's access policy is not what was reviewed — which is precisely a thing that should stop a release rather than be discovered afterwards.

The check reports what it examined: which host, which hash, and — when they differ — that the LIVE file is authoritative for behaviour while the REPO copy is authoritative for intent, so the operator knows which way to reconcile.

## SEQUENCING WITH 253 / WAVE D

This is the payoff and it should be said plainly: once the stage exists, **the file shrinking as deploy entries die becomes a reviewed commit plus a stage re-run, instead of a root session.** The 253 removals and the Wave D deletions stop needing privileged hands at all — they become diffs, which is what "ships as code" means.

259 lands first; 253's removals then ride it.

## TWO FACTS FOUND WHILE VERIFYING

1. **The header is stale about its own location** — it says *"see tmp/niue-sshdoers in the statbus repo for a copy"* while the file lives at `ops/niue/sshdoers`. Fix it in this unit; a pointer to a path that no longer exists is how the repo copy came to be treated as a souvenir rather than a source.
2. **STATBUS-258's entry is already expressible.** The file declares `match hexdigits`, where `#` matches any hex digit at runtime — used today for pg_regress's 40-char SHA. So `upgrade apply <40hex>` needs **no new grammar and no new sshdo capability**, only a line. That de-risks 258 materially and is worth knowing before it is built.

## NOT SPECIFIED

Whether other hand-managed root state on these hosts (unit files, ACLs) should join the same stage. Probably yes, and by the same argument — but each deserves its own evidence rather than being swept in on this one's reasoning.
---

author: foreman
created: 2026-08-20 06:06
---
KING APPROVAL (2026-08-20 morning) — the design in comment #1 is approved as ratified, exactly as written: /etc/sshdoers becomes a stage of ops/setup-ubuntu-lts-24.sh (the existing repo-tracked root provisioning path), independently runnable; a world-readable /etc/sshdoers.sha256 is published beside the root-owned file; drift FAILS THE RELEASE PREFLIGHT; explicitly NOT a ./sb subcommand (the product must not know CI doors). The existing `match hexdigits` grammar means 258's future `upgrade apply <40hex>` entry is one line.

Execution order pinned by the King:
1. Engineer builds the stage + the preflight drift check (this ticket).
2. The FIRST stage run on niue requires the King's root session — the exact command list must be pre-declared per the standing box-access rule.
3. Only after the stage is live does deploy-to-dev's marked block swap apply-latest → upgrade apply "$SHA".

Architect verdict required on the diff before landing, as always.
---

author: architect (relayed by foreman)
created: 2026-08-20 06:15
---
VERDICT on the engineer's plan (2026-08-20): (a) faithful implementation — APPROVED. (b) COMPARE-FIRST first-run protocol — RATIFIED, an improvement on the design: nothing has ever synced repo↔live, so the first root session compares read-only and STOPS on difference; reconciliation is a reviewed commit (live wins on first contact — live is authoritative for behaviour, repo for intent) and the first stage run is byte-wise a no-op. Prove the machinery while changing nothing.

(c1) Preflight read account: devops@<host>, env-overridable. The read needs no privilege (hash file world-readable); unreachable = FAIL with loud SKIP_SSHDOERS=1 bypass — cannot-verify is not verified.

(c2) MODE — REVERSED, hazard not preference: sshdo runs AS THE SLOT USER via command= in authorized_keys and must read /etc/sshdoers as that user (unless setuid). Setting 0600 root:root could deny every CI command fleet-wide in one stroke. The stage PRESERVES the live mode on an existing file — reports it, changes nothing. This also corrects the original design's unverified premise that no slot user should read the policy; the hash file survives on the better justification (drift detection without parsing + recording what was installed). The real mode arrives with step 3 of the first run.

(c3) SSHDOERS_REF — REQUIRED, no default, never master. A security artifact must be commit-addressed (canonical-commit-naming); installing whatever master holds at run time means nobody can name the live policy afterwards.

COMMAND LIST ADDITION: step 7 also proves demo's entry (ssh statbus_demo@niue "cd ~/statbus && ./sb upgrade apply-latest" must be ALLOWED) — the newest entry, the named casualty of a wrong reconcile, and its loss would be silent (the 04:23 UTC scheduled trigger just starts failing). Test the entry most likely to be missing.

Build go approved on the architect's side; command list relayed to the King with these three changes.
---
<!-- COMMENTS:END -->
