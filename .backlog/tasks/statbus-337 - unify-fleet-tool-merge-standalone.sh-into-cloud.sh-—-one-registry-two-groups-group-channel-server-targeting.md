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
## The principle

One fleet, one tool. Every box the SSB operates is reached the same way
(SSH, `cd statbus`, `./sb ...`) and answers the same questions (version,
channel, name, health). The only thing that differs per box is the SSH
address. Two scripts that differ only in that one field means every
improvement is written twice and the operator needs two commands to see
the fleet.

## Ground truth (2026-09-06)

- `cloud.sh` (30 KB): registry is a flat list of niue slot users,
  `SERVERS="statbus_dev statbus_demo statbus_et statbus_jo statbus_ma
  statbus_mw statbus_ug statbus_ua statbus_gh"` (9 boxes); transport is
  `ssh <slot-user>` on niue. Verbs: `status health install rescue upgrade
  notify tail create wipe inspect` plus retired `migrate-up/down` stubs.
- `standalone.sh` (26 KB): registry is `HOSTS=("no|rune.statbus.org|no.statbus.org")`
  (1 box, three fields: code, fqdn, public domain); transport is
  `ssh statbus@<fqdn>`. Verbs: `status install rescue upgrade notify inspect
  wipe ssh import reimport` (the last three are Norway/BRREG-specific and run
  `samples/norway/brreg/*.sh` on the box).
- Both carry the same channel-awareness code (the 2026-09-02 change landed
  in both). Both support targets `all | <box> | stable | prerelease`.
- `standalone.sh` is referenced by: `install.sh`, `test/auth_for_dev.statbus.org.sh`,
  `doc/install-statbus.md`, `doc/CLOUD.md`, `doc/upgrade-timeline.md`,
  `doc/archive/recovery-arc-flaw-timeoutstartsec.md`, and `cloud.sh` itself.

## Work

### M1. One registry, entries carry their transport

In `cloud.sh`, replace `SERVERS` and the imported `HOSTS` shape with one
registry where each entry has: code, group (`cloud | standalone`), SSH
target (`statbus_<code>` for cloud, `statbus@<fqdn>` for standalone), and
public domain. One helper resolves an entry to its `ssh` invocation; every
verb goes through it. Display name and channel keep coming from the box
itself (`./sb config show`), never from the registry.

### M2. Targets span groups

`all`, a box code, a channel (`stable | prerelease`, resolved live from each
box), or a group (`cloud | standalone`). `./cloud.sh status` shows all 10
boxes in one table with version, channel, name, group.

### M3. Group-only verbs refuse plainly

`create`, `wipe`, `inspect` are niue slot lifecycle and declare themselves
cloud-group-only: targeting a standalone box prints one line saying so and
exits 2. The Norway BRREG verbs (`import`, `reimport`) and `ssh` are
standalone-group-only today; keep them, mark them the same way, and let the
registry entry (not the verb) decide eligibility so a second standalone box
inherits them. When the target is `all`, the registry-per-entry rule applies:
the command processes every eligible entry, prints one skip line for each
ineligible entry, and exits 0 when at least one eligible entry ran.

### M4. Clean break

Delete `standalone.sh` in the same commit. Update every reference listed
above to the `./cloud.sh` form. `grep -rn standalone.sh --include='*.sh'
--include='*.md' --include='*.yaml' .` outside `tmp/` and `.backlog/` must
return only this ticket's own history comment in `cloud.sh`.

## Acceptance

1. `./cloud.sh status` shows all 10 boxes (9 cloud + rune) with version,
   channel, name, group.
2. `./cloud.sh install stable <version>` targets both groups; a dry-run or
   read-only verification is enough for this ticket (no box is upgraded by
   it).
3. `create|wipe|inspect` refuse a standalone target plainly; `import|reimport|ssh`
   refuse a cloud target plainly.
4. `standalone.sh` is gone; zero dangling references.
5. bash tests under `test/` cover: registry parsing, target resolution
   (all / code / channel / group), transport selection, and the group-only
   refusals, without SSH (stub the transport helper).
6. Read-only verification against the live fleet: `./cloud.sh status` and
   `./cloud.sh health` succeed for all 10; nothing else is run live.

## Non-goals

Changing what any verb does on the box; changing the upgrade service;
adding boxes. `STANDALONE_TRUST_KEY_USER` and cloud's equivalent become
one variable name; document the rename at the point of entry.

## Staffing

One headless implementer, test-first with the stubbed transport; one
adversarial review; the coordinator runs the read-only live verification.

## Original description (verbatim)

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
