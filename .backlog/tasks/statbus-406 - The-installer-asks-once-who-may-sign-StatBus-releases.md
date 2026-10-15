---
id: STATBUS-406
title: The installer asks once whether to trust the Statistics Norway release signer
status: In Progress
assignee: []
created_date: '2026-09-24 15:35'
updated_date: '2026-10-15 20:25'
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

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
### North Star
On a first install the operator is asked once, in plain words, whether to trust the Statistics Norway release signer, sees the key fingerprint before answering, and is never asked again.

### Zoom out
Every StatBus release is signed, and the installer only accepts releases signed by a key the operator has chosen to trust. That trust is a deliberate decision, so it is asked, not assumed. It is also a one-time decision: once given, the answer is saved and every later run, including a rerun after an interrupted install, uses it silently. Showing the fingerprint lets the operator check the key out of band. Managing further signers is not part of installing; the installer offers exactly one.

### Zoom in
- **Incident, Finland 2026-09-24 (v2026.09.2):** the signer question came before the step table, used GitHub and key-management wording, then opened `Add additional trusted signer? (GitHub username, or Enter to skip)`; a separate Trusted signers step ran later (`tmp/finland-transcript-actual.txt:88-104`).
- **Shipped (v2026.09.3):** `436628aed` (saved consent needs first-install signer provenance), `67cfa7e6d` (consent kept on interrupted rerun), `333434efa` (first-run consent resumes after crash recovery, VM job `108718085344`). The question now sits inside the Trusted signers step, after the setup questions, with no additional-signer loop.
- **Proof, unit:** `TestInteractiveSignerQuestionHasOneOwnerAndNoAdditionalLoop`, `TestTrustGitHubUserRunsBeforeDispatch` (`cli/cmd/install_trust_order_test.go`), `TestFreshUnattendedConfigThenTrust` (`cli/cmd/install_trust_input_test.go`), green 2026-10-15.
- **Proof, real guest (STATBUS-474, 2026-10-08):** `0-interactive-setup-choices.sh` drives the real `install.sh` on a PTY and fails on any unexpected question. Observed: the plain explanation, `jhf (Jorgen H. Fjeld)`, fingerprint `SHA256:MU8OCWwTrZ6zkh0nZp/jmZpdgxe6rgBRDdlV87TqMIE`, one `Trust key(s) from github.com/jhf? [Y/n]`, then `[7/18] Trusted signers DONE`; driver count `signer=1`, no re-ask, no additional-signer prompt.

### Closing review
- **Memory:** none needed.
- **Documentation:** none needed.
- **Cleanup:** none.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 One plain trust question shows the signer and fingerprint before anything is saved (`TestFreshUnattendedConfigThenTrust`; real guest transcript in STATBUS-474)
- [x] #2 The saved answer satisfies the later Trusted signers step and every rerun, with no second prompt and no additional-signer loop (`TestInteractiveSignerQuestionHasOneOwnerAndNoAdditionalLoop`, `TestTrustGitHubUserRunsBeforeDispatch`)
- [x] #3 A real interactive install on a PTY asks the signer question exactly once and completes (`0-interactive-setup-choices.sh`, green 2026-10-08, STATBUS-474)
- [ ] #4 [Owner] Decide whether web-interface management of further release signers is still wanted, and record it in Implementation Notes. Yes: file it as a new ticket, then check this and set Done. No: check this and set Done.
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
### Evidence
- **AC1-2:** green locally on master, 2026-10-15.
- **AC3:** the scenario still carries `HARNESS_SKIP_DEFAULT`, so it is not in the default release gate; its one run is the local 2026-10-08 guest recorded on STATBUS-474.
- **Superseded criterion:** the restyle named `0-interactive-trusted-signer.sh`, never written; `0-interactive-setup-choices.sh` covers it.
<!-- SECTION:NOTES:END -->
