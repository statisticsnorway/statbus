---
id: STATBUS-406
title: The installer asks once whether to trust the Statistics Norway release signer
status: In Progress
assignee: []
created_date: '2026-09-24 15:35'
updated_date: '2026-09-24 18:44'
labels:
  - release-bug
  - install
  - security
  - ux
dependencies: []
priority: high
type: bug
ordinal: 359000
---

## Status 2026-09-24

**In Progress.** `8543f493a`: `cli/cmd/install_trust_input_test.go` and `install_trust_order_test.go` cover #1-2, one fingerprinted choice persisted before the signer step. #3's `0-interactive-trusted-signer.sh` is absent. **Remaining:** exercise exactly one choice and a later OK step without an additional-signer loop on a VM.

Baseline: `origin/master` at `373d15fc3`. Criterion disposition and remaining positive targets are above; the acceptance criteria below remain authoritative. An authored but unrun VM scenario is **proof pending**, not met.

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
