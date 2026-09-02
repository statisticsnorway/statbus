---
id: STATBUS-340
title: >-
  phone-home: opt-in version/channel/mode reporting — field facts for the
  upgrade fan, EOL decisions, and support
status: To Do
assignee: []
created_date: '2026-09-02 11:29'
labels:
  - ops
  - release
  - product
dependencies: []
priority: low
type: feature
ordinal: 333000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Issue: the STATBUS-339 fan (which source releases must prove a direct hop to each candidate) is a guess — N=3, last three by the ledger. The King's observation: only field data can pick that number and those versions. Our own ten boxes are fully visible (cloud.sh/standalone.sh), but external standalone installations — the deployment goal — are invisible, and theirs are the hops that matter.

Design (for the King's ruling before any build): a minimal, OPT-IN phone-home. Payload: version, channel, deployment mode — nothing else; inspectable by the operator. Opt-in as a visible .env.config line documented at install (entry-way file discipline); the system fully functional without it — NSOs are sovereignty-sensitive and some are air-gapped. Note: upgrade discovery already reaches GitHub anonymously, so this is comparable exposure made explicit and consensual.

What it buys: the 339 fan computed from the real field distribution instead of N=3; honest EOL decisions (the db-seed hold class — 'is any box still on ≤ v2026.05.6?'); support knowing 'what are you running' before the first email.

Until it exists, N=3-by-ledger stands as the explicit stand-in (recorded on 339).

Acceptance (post-ruling): opt-in flag documented at its point of entry; payload exactly the ruled fields; receiving endpoint decided (simplest honest option); 339's fan selection gains an optional field-data source; a box with the flag off behaves identically to today.
<!-- SECTION:DESCRIPTION:END -->
