---
id: STATBUS-406
title: The installer asks once whether to trust the Statistics Norway release signer
status: To Do
assignee: []
created_date: '2026-09-24 15:35'
updated_date: '2026-09-24 18:44'
labels:
  - install
  - security
  - ux
dependencies: []
priority: high
type: bug
ordinal: 359000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Installation asks one plain question about trusting the Statistics Norway release signer, shows the key fingerprint, persists the answer, and later reports the signer step complete. The terminal does not enter an additional-signer loop.

## Evidence, 2026-09-24

The Finland flow asked for trust before the step table, showed the fingerprint, offered an additional-signer prompt, and later ran the signer step (`/Users/jhf/ssb/statbus/tmp/finland-transcript-actual.txt:88-102`, `/Users/jhf/ssb/statbus/tmp/finland-transcript-2-actual.txt:107-114`). Master separates early input and step-16 handling at `cli/cmd/install.go:107,163,2572-2588` at `7a9cf707e`. No verified web signer-management feature is part of this ticket.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 `cli/cmd/install_trust_input_test.go` observes one plain trust choice with fingerprint before persistence.
- [ ] #2 `cli/cmd/install_trust_order_test.go` observes the persisted choice before the later signer step and no second prompt.
- [ ] #3 `new: test/install-recovery/scenarios/0-interactive-trusted-signer.sh` records exactly one trusted-signer choice, the fingerprint, a later OK result, and no additional-signer terminal loop.
<!-- AC:END -->
