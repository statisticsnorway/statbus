---
id: STATBUS-499
title: >-
  Decide whether the security stage may keep piping the vendor installer into a
  root shell
status: In Progress
assignee: []
created_date: '2026-10-13 13:44'
updated_date: '2026-10-13 13:53'
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

OWNER DECISION 2026-10-13: keep the vendor pipe. Use sudo appropriately, or not at all - we are already root when this runs. Consequence, and why this is now a one-line change rather than a redesign: STATBUS-492 added a guard so the script refuses a plain sudo from an operator home and requires a root login shell, so by the time Stage 4 runs HOME is /root and the vendor script no longer inherits an operator home. That concern is therefore already closed by the guard, which has its own pinned test. What remains is only the redundant sudo in the pipeline, to be dropped once the same file is free (STATBUS-491 is being edited in it right now). Deliberately NOT done: no test asserting that sudo is absent from that line - that would assert about removed code rather than behaviour, and the behaviour that makes the line safe is already pinned by the 492 test.

Landed 2026-10-13: the pipeline is now `curl -s https://install.crowdsec.net | bash`, with the decision recorded in the comment above it. No test accompanies this on purpose: an assertion that sudo is absent would be about removed code rather than behaviour, and the behaviour that makes the line safe (a root login shell with HOME=/root) is already pinned by the STATBUS-492 test. bash -n parses.
<!-- SECTION:NOTES:END -->
