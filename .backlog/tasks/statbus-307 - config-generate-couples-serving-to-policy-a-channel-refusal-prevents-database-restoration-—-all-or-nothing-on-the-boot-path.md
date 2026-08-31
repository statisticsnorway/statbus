---
id: STATBUS-307
title: >-
  config-generate-couples-serving-to-policy: a channel refusal prevents database
  restoration — all-or-nothing on the boot path
status: In Progress
assignee:
  - mechanic
created_date: '2026-08-28 21:37'
updated_date: '2026-08-31 13:17'
labels:
  - upgrade
  - cli
  - config
dependencies: []
priority: high
type: bug
ordinal: 300000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
NORTH STAR: a box's ability to serve must never depend on resolving upgrade policy. Today it does, at exactly one joint: config generate is all-or-nothing on the boot path, so a refusal about which release CHANNEL a box follows prevents its DATABASE from being brought back up.

THE CAUSAL CHAIN THAT EXPOSED IT (STATBUS-298's checkpoint read, architect-confirmed): an earlier legitimate teardown leaves the db down, expecting the next boot's EnsureDBUp to restore it. The boot runs config generate first (service.go:2103, structurally before EnsureDBUp at :2113 — correctly so, the config feeds everything after). When config generate REFUSES on the 254 channel-ambiguity guard (both UPGRADE_ROLE and UPGRADE_CHANNEL present — a policy question), the boot returns before :2113 and the database that should have come back never does. The refusal is CORRECT; the channel question is genuinely ambiguous. What is wrong is the blast radius: two keys disagreeing about release policy cost the box its database.

THE DEFECT, precisely: config generate conflates two outputs with different criticality — (a) what the box needs to SERVE (.env, compose config, ports, secrets wiring) and (b) upgrade policy resolution (role→channel). A refusal in (b) currently withholds (a). Under 298's fix the failure is loud, once, exit-78 — strictly better than five futile restarts — but the box still ends db-down over a policy disagreement.

THE SHAPE TO EXPLORE (restructure, deliberately NOT this round — architect's ruling: not a same-day change): separate the serve-critical generation from the policy resolution, so a policy refusal degrades the box to serving-but-not-upgrading (with the refusal loud in the journal and the marker file) instead of not-serving. The 298 marker/exit-78 machinery is the natural integration point: policy-refused becomes a parked-but-serving state, the operator's install.sh run resolves it. Design questions: which config outputs are genuinely policy-dependent; whether a stale-but-valid previous .env can serve while policy is unresolved; how the refusal surfaces without being ignorable forever.

CROSS-REFERENCES: STATBUS-298 (the loud-once fix this coupling survives), STATBUS-254 (the guard, correct), STATBUS-297 (where the chain was first observed live).

WHAT IS ACHIEVED: a policy disagreement can never take a database down; refusals about upgrades park the upgrade, not the box.
<!-- SECTION:DESCRIPTION:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
SMALL HONEST VERSION LANDED at 3ff11f1d6 (the architect's tonight-shippable design): the refusal branch forks on prior-.env existence — fresh box refuses hard (298's exit-78 unchanged), configured box parks (the marker IS the park at boot time; no db connection exists yet for a row-level park) and falls through to EnsureDBUp so the database returns and the box serves. Structural test pins the fork, the single exit site, and the exit-free fall-through window; red-verified. ONE INTERPRETATION FLAGGED FOR THE ARCHITECT (mechanic's, honest): no explicit downstream guard blocks upgrade scheduling while parked — the block is by absence-of-refresh (config generate failed so nothing new exists to act on; the daemon's loaded config and on-disk .env are unchanged). OPEN QUESTION for his next pass: can a PREVIOUSLY-SCHEDULED pending row still execute against the ambiguous config state, and if so does executeUpgrade's own path handle the refusal acceptably (298's machinery) or does the marker need a discover/executeScheduled check? TICKET STAYS OPEN for that ruling + the full serve-config/policy-config restructure as the complete form.

**Architect ruling (2026-08-29): block-by-absence REJECTED — explicit parked-state execution guard required before rc.17.** The parked box's protection against executing a pre-scheduled public.upgrade row currently holds only because the upgrade path happens to need a fresh config — a property held by accident, unstated, that a refactor tolerating stale config would silently remove with nothing going red. The park exists precisely because channel policy is ambiguous; executing a scheduled row in that state could install a wrong-channel candidate on a production box (the 291 harm). Reachable: row scheduled → unconditional UPGRADE_ROLE write on a pre-254 box → boot. Fix: the execution entry point reads the existing marker (307 already built it) and refuses with the same actionable text as the boot refusal. Assigned: mechanic (holds the 298/307 file region), tonight.

**Execution guard LANDED at 3d102d676** (foreman-reviewed diff): the arriving job's own first act in claimScheduledUpgrade — the one function both dispatch paths share (install verb's inline dispatch + daemon's periodic pickup), so a single change covers both. Marker present → refuse surfacing the original refusal text + timestamp; marker unreadable → refuse (fails closed per the 039/111/159 doctrine); no marker → unchanged fall-through. Deliberately distinct in the comment from the row-level recovery_parked_at park. Structural tests pin guard-before-park-read + both refusal branches + genuine-conditional; red-verified via guard-deleted scratch copy; full internal/upgrade suite green, -race clean. TICKET REMAINS OPEN for the full serve-config/policy-config restructure (the architect's not-same-day complete form); tonight's two landings (boot-time park-and-serve fork + this dispatch guard) close the acute halves.
<!-- SECTION:NOTES:END -->

## Comments

<!-- COMMENTS:BEGIN -->
author: architect
created: 2026-08-31 12:40
---
**FULL RESTRUCTURE DESIGN — for the King's approval.**

**Purpose, in two sentences.** A box's ability to serve must never depend on answering which release channel it follows. Today one unanswerable policy question withholds the entire generated configuration, and this design makes the policy answer optional to serving without making it ignorable.

## The finding that makes this SMALL

The restructure sounds like untangling a generator. It is not. **The policy output is exactly two keys.**

`ResolveUpgradeRole` (`cli/internal/config/upgrade_role.go:187`) returns a role and a channel string — nothing else. Everything else `config generate` produces (ports, bind addresses, database credentials, compose wiring, Caddy files) is computed from deployment mode and slot facts that have **nothing to do with release policy**.

**So the coupling is one ABORT, not an interleaving.** The work is to stop one failure from cancelling ~50 unrelated outputs.

## Part 1 — policy resolution becomes a RESULT, not a gate

`config generate` computes every serve-critical output unconditionally. A `ResolveUpgradeRole` failure yields an *unresolved policy* result instead of aborting the run.

**THE RULE THAT MATTERS MOST: the two policy keys are OMITTED, never defaulted.** Absent is the honest representation of unknown. Defaulting to `stable` would be a **fabricated policy**, and a fabricated policy can install a wrong-channel candidate on a production box — the STATBUS-291 harm arriving through a helpful default. **An unresolved question must never acquire an answer by convenience.**

## Part 2 — the blocking half ALREADY EXISTS

Both halves that stop a parked box from upgrading are landed: the marker carrying the refusal text (3ff11f1d6) and the dispatch guard in `claimScheduledUpgrade` that refuses on its presence (3d102d676).

**So this design changes nothing about blocking. It changes only what happens to the OTHER outputs.** Assert the existing behaviour in tests; do not rebuild it.

## Part 3 — visibility, by reuse rather than a new mechanism

The unresolved-policy state is **a state**, and STATBUS-308 already pushes state to `public.system_info` and surfaces it on the upgrade page — including the staleness arm, so a box that stops reporting is visible too.

**Push the policy-unresolved state through 308's existing channel. No second watchdog.** A parked box reads as parked; a silent box reads as stale.

## What the FULL form buys over the small version already landed

Worth stating plainly, or "we already park and serve" looks like enough.

**The landed version serves on the STALE prior `.env` — nothing regenerates.** A port change, a credential rotation, or a Caddy update made while policy is ambiguous does not take effect. **The full form regenerates everything it can**, leaving only the two policy keys unresolved. That is the entire gain, and it is the difference between a box that is frozen and a box that is merely not upgrading.

## THE ONE REAL INTEGRATION RISK

**Omitting a key only helps if no reader invents a value for it.** Every consumer of `UPGRADE_CHANNEL` must tolerate absence and refuse rather than default. **Enumerate the readers before building** — a single reader that falls back to `stable` on absence reintroduces the fabricated policy through the back door, and it would do so silently.

## Acceptance criteria

1. `config generate` writes a complete serve-critical `.env` when `ResolveUpgradeRole` fails.
2. The two policy keys are **omitted, never defaulted**, when policy is unresolved.
3. A box with ambiguous policy **and a changed port or credential picks up that change on the next boot** — proving fresh generation, not stale reuse.
4. Every reader of `UPGRADE_CHANNEL` is enumerated, and each refuses rather than defaults on absence.
5. The marker and dispatch guard behave exactly as landed (asserted, not rebuilt).
6. The unresolved state appears in `system_info` and on the upgrade page via 308's existing path.
7. A box with **resolved** policy generates byte-identically to today — no regression on the healthy path.
8. Red-verified: reintroducing a default for the channel fails a test.
---

author: foreman
created: 2026-08-31 13:17
---
KING'S PRINCIPLE (2026-08-31, supersedes the pending approval question on the filed design): When an installation runs ./sb config generate, the DEFAULT values shall be those suitable for an NSO STANDALONE installation. Anything else must be specified. Confirmed in discussion: SITE_DOMAIN is the one key with no honest default — and as such it must be specified (standalone mode with an unspecified domain refuses with an actionable message rather than generating a config that cannot serve). Foreman's verified groundwork for the re-derivation: config.go:352 currently defaults CADDY_DEPLOYMENT_MODE to 'development' (the direct inversion of the principle); gen()/f.Generate writes defaults into .env.config on first generate, so every existing box carries the mode key explicitly and a default flip touches only genuinely fresh installations; defaultRoleForMode's equivalence concern dissolves for the same reason; cloud slots set 'private' explicitly (create-new-statbus-installation.sh:361); canary is explicit-only by design. The filed partial-generation design is NOT approved as-is — architect re-derives 307 under this principle (it may shrink to: flip the mode default, add the standalone SITE_DOMAIN refusal, keep fail-fast on incoherent explicit input).
---
<!-- COMMENTS:END -->
