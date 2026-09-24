---
id: STATBUS-386
title: >-
  Disk preflight refusal must not be reported as SYSTEM UNUSABLE
status: To Do
assignee: []
created_date: '2026-09-24 16:42'
updated_date: '2026-09-24 16:42'
labels:
  - install
priority: high
type: bug
ordinal: 1
---

## Finland v2026.09.2 evidence (2026-09-24)

The install's disk-space refusal printed `SYSTEM UNUSABLE / no named invariant`.
The triage identifies this as the install.sh abort path at
`install.sh:770-792`, while `cli/cmd/install.go:95-101` already defines the
plain `installPreflightRefusalError` path and `install.sh:735-737` has the
intended remedy. This is a refused precondition, not a broken system.

## Done when

Disk, root, and trusted-signer precondition refusals exit through the plain
preflight refusal path, with no support-bundle/invariant-breach wording.
