---
id: STATBUS-401
title: Step 15 creates the first administrator through a private prompt
status: To Do
assignee: []
created_date: '2026-09-24 15:35'
labels:
  - install
  - users
  - security
dependencies: []
priority: high
type: bug
ordinal: 354000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Interactive installation asks for the first administrator email, name, and password twice with hidden typing, then creates that administrator. Additional users are invited from the web interface. File-based user creation remains available for unattended installation. Terminal and log output protect password values.

## Evidence, 2026-09-24

Finland step 15 stopped because `.users.yml` was absent. After the operator copied and edited an example file, the step printed database command output and a password column.

## Proving scenario

Extend `0-happy-install` to inspect the transcript for protected credential output. A terminal-driven fresh-install scenario answers the administrator prompts and signs in through `/rest/rpc/login` with the created account.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Interactive step 15 asks for the first administrator email, name, and password confirmation with hidden password entry.
- [ ] #2 Step 15 creates the first administrator and installation continues to completion.
- [ ] #3 The terminal and install log protect password values and show only plain success text.
- [ ] #4 Unattended installation can create users from its configured user file.
<!-- AC:END -->
