---
id: STATBUS-307
title: >-
  config-generate-couples-serving-to-policy: a channel refusal prevents database
  restoration — all-or-nothing on the boot path
status: In Progress
assignee:
  - mechanic
created_date: '2026-08-28 21:37'
updated_date: '2026-08-28 23:07'
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
<!-- SECTION:NOTES:END -->
