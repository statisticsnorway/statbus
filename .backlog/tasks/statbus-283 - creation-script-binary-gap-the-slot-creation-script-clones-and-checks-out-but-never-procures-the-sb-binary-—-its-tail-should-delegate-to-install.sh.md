---
id: STATBUS-283
title: >-
  creation-script-binary-gap: the slot-creation script clones and checks out but
  never procures the sb binary — its tail should delegate to install.sh
status: To Do
assignee: []
created_date: '2026-08-27 16:47'
updated_date: '2026-08-27 17:00'
labels:
  - ops
  - cloud
dependencies: []
priority: medium
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
<!-- COMMENTS:END -->
