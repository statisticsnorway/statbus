---
id: STATBUS-269
title: >-
  sshdoers-host-validate: Stage 8 should refuse when ops/<host>/ does not exist
  — a typo'd SSHDOERS_HOST currently sends the operator chasing a missing file
status: To Do
assignee: []
created_date: '2026-08-27 12:58'
labels:
  - ops
dependencies: []
priority: low
type: enhancement
ordinal: 262000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Deferred refinement from STATBUS-259's preamble-fix review (architect, 2026-08-27). Stage 8 derives the host from hostname --fqdn (short name) or SSHDOERS_HOST, then fetches ops/<host>/sshdoers. A mistyped SSHDOERS_HOST — or a container identity — produces an error message naming ops/<typo>/sshdo as "holding the canonical copy" when no such directory exists, sending the operator chasing a missing file instead of the typo.

The fix, as ruled: validate that ops/<host>/ EXISTS (in the repo tree at SSHDOERS_REF) before using the derived name, and refuse with "no reviewed policy directory for host X — is SSHDOERS_HOST correct?" One check covers containers and typos alike.

WHAT IS ACHIEVED: a wrong host name is reported as a wrong host name, not as a missing canonical file.
<!-- SECTION:DESCRIPTION:END -->
