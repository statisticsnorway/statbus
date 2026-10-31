---
id: STATBUS-554
title: >-
  Setup on a plain box cannot confirm SSH access or Docker for statbus, because
  the account is created in a later stage
status: To Do
assignee: []
created_date: '2026-10-31T01:48:00Z'
updated_date: '2026-10-31T01:49:00Z'
labels:
  - setup
  - install
dependencies: []
priority: high
type: bug
ordinal: 477204
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
North Star: setup.sh on a plain Ubuntu box finishes with every check green on its first run, ready for the operator's install.

### Zoom out
Stages 2 (SSH access confirmation, STATBUS-495/540) and 5 (Docker usable by the service account, STATBUS-500) act on the service account statbus, but Stage 7 creates it. Uganda and every LXD scenario already had statbus (the harness creates it, vm-bootstrap.sh), so neither ever met a plain box. On a plain box the first run therefore skips SSH hardening and fails the Docker check, exit 1; a second run would pass. STATBUS-500 AC5 expected this check to pass on the next real preparation.

### Zoom in
Plain Hetzner cx33, Ubuntu 26.04 (statbus-manual), setup.sh at c1153315a, non-interactive, SKIP_STAGES=4, 2026-10-31 01:41 UTC. Log: '[ERROR] populate_authorized_keys: user statbus has no home directory', 'Could not install keys for statbus. Nothing has been changed', then 'WARN statbus does not exist yet (it is created in a later stage)', and the summary '2 verification(s) failed: Remote access confirmed before hardening; Docker usable by statbus'. After the run statbus exists (uid 1000, docker group, 1 authorized key).

### Closing review
Documentation needed: the setup script's stage comments state where the service account is created and why that comes before the stages that use it. No memory change.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 A test reproduces it: stages run in order on a box without statbus, and Stage 2 or Stage 5 acts on a missing account (red)
- [ ] #2 The service account exists before every stage that uses it (Stage 2 key install and confirmation, Stage 5 docker grant and check); the same test is green
- [ ] #3 A plain-box run of the released setup.sh finishes with exit 0 and no failed verification (log recorded)
<!-- AC:END -->
