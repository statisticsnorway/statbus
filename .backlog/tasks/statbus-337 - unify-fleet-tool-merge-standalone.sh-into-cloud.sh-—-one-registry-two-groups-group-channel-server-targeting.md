---
id: STATBUS-337
title: >-
  unify-fleet-tool: merge standalone.sh into cloud.sh — one registry, two
  groups, group/channel/server targeting
status: To Do
assignee: []
created_date: '2026-09-02 10:37'
labels: []
dependencies: []
priority: medium
ordinal: 330000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Issue: cloud.sh and standalone.sh are the same tool split by transport history.
Every improvement is made twice (the 2026-09-02 channel-awareness work was literally implemented in both), the fleet view needs two commands, and channel targeting cannot span groups even though channels are group-agnostic (rune is prerelease alongside dev).

Fix: merge into ONE tool handling two groups.
One registry; each entry carries slot code, transport (niue slot user vs user@host), display-name source, and group (cloud | standalone).
status/health/install/rescue/tail/notify/upgrade iterate all entries via per-entry transport.
Targets: all, a server, a channel (stable | prerelease, live-resolved), or a group (cloud | standalone).
Niue-only lifecycle verbs (create, wipe, inspect) declare themselves cloud-group-only and refuse other targets plainly.
Clean break per the internal-code rule: standalone.sh deleted in the same commit, every doc/ops reference updated (grep doc/ ops/ .github/ for both names).

Acceptance: one command shows the whole fleet (10 boxes) with version, channel, name; ./cloud.sh install stable <version> spans both groups; standalone.sh is gone with zero dangling references; read-only verification against the live fleet.
<!-- SECTION:DESCRIPTION:END -->
