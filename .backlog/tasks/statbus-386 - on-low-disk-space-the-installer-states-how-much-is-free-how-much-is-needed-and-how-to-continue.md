---
id: STATBUS-386
title: >-
  On low disk space, the installer states how much is free, how much is needed,
  and how to continue
status: To Do
assignee: []
created_date: '2026-09-24 16:42'
updated_date: '2026-09-24 14:53'
labels:
  - install
dependencies: []
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

## Goal

When a precondition is unmet (disk space, root, trusted signer), the installer
exits through the plain preflight-refusal path with a short message: what it
found, what it needs, and the command to continue.

## Done when

- On a host with too little disk, the operator sees free space, required space,
  and the exact rerun command (with `STATBUS_MIN_DISK_GB` for a deliberate
  override).
- Root and trusted-signer refusals use the same plain preflight format.
- The message reads as a precondition to satisfy, and install.sh exits with the
  preflight-refusal code.
