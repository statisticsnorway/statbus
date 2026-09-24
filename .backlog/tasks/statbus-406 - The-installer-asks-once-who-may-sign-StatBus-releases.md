---
id: STATBUS-406
title: The installer asks once who may sign StatBus releases
status: To Do
assignee: []
created_date: '2026-09-24 15:35'
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
Installation asks one plain question about trusting the Statistics Norway release signer, shows the key fingerprint, records the answer, and reports the signer step as complete later in the run. Additional signers are managed after installation through the web interface.

## Evidence, 2026-09-24

Finland was asked about a release signer before the step table and then saw a separate trusted-signers step. The question used GitHub and key-management terminology and offered an additional-signer loop.

## Proving scenario

Extend signer order and input tests to count one prompt per run. A terminal-driven fresh-install scenario records one plain question, the fingerprint, and a later OK result for the signer step.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Installation asks one plain question about trusting the Statistics Norway release signer.
- [ ] #2 The question shows the signing key fingerprint before recording trust.
- [ ] #3 The later signer step reports OK from the recorded answer.
- [ ] #4 Additional signer management is available through the web interface after installation.
<!-- AC:END -->
