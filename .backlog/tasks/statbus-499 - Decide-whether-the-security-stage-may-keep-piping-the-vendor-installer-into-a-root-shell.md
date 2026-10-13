---
id: STATBUS-499
title: >-
  Decide whether the security stage may keep piping the vendor installer into a
  root shell
status: To Do
assignee: []
created_date: '2026-10-13 13:44'
labels:
  - install
  - hardening
  - security
dependencies: []
priority: medium
type: task
ordinal: 425204
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
QUESTION, raised by the coordinator reviewing the Uganda prepare run on 2026-10-13 and left for the owner to decide. ops/setup-ubuntu-lts.sh sets up the CrowdSec apt repository with: curl -s https://install.crowdsec.net | sudo bash. That executes whatever the vendor serves at that moment, as root, inside a hardening stage. OWNER LEANING, 2026-10-13: we cannot avoid trusting the security tool itself, so this is not the same class as the Docker repository setup (which we do ourselves with the vendor key and an apt source); and downloading the script first, rather than piping it, gives us little, since either way the vendor content runs as root. Two details that remain worth recording: (1) the invocation runs as root from the operator home, so the vendor script inherits a non-root HOME - sudo inside a sudo, which is not sensible even if it works; (2) the Docker path in the same script already does the verifiable thing (import the key, write the source) and could be copied for CrowdSec if we decide to. DECIDE: keep the pipe as is, download-then-run, or set up the CrowdSec repository ourselves with the vendor key and an apt source, plus whether to run it from a root login shell rather than the operator home.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 The decision is recorded in this ticket, with the reasoning, and the code either matches it or the ticket says which ticket changes it.
- [ ] #2 Whichever way it goes, the invocation no longer inherits the operator home as root: it runs in a root login shell or from a neutral working directory, with the HOME in effect recorded.
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Filed 2026-10-13 while fixing STATBUS-498 in the same stage. Not a bug report: the owner has already said the trust in the security vendor is unavoidable, so this exists to make the choice explicit and to capture the two small details (the operator-home HOME, and the consistency with the Docker repository setup) rather than to argue for a change.
<!-- SECTION:NOTES:END -->
