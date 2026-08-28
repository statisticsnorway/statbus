---
id: STATBUS-307
title: >-
  config-generate-couples-serving-to-policy: a channel refusal prevents database
  restoration — all-or-nothing on the boot path
status: To Do
assignee: []
created_date: '2026-08-28 21:37'
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
