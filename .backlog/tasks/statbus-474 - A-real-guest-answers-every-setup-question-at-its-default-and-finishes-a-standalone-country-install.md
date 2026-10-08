---
id: STATBUS-474
title: >-
  A real guest answers every setup question at its default and finishes a
  standalone country install
status: To Do
assignee: []
created_date: '2026-10-08 15:16'
labels:
  - install
  - installer
  - test
dependencies:
  - STATBUS-466
priority: medium
ordinal: 400204
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
NORTH STAR: the interactive setup questions (mode, domain, country name, country code; STATBUS-400/466) are proven in a real Ubuntu guest through install.sh, not only by unit tests and a PTY run of the binary.

WHY THIS TICKET EXISTS: STATBUS-400 AC2 named test/install-recovery/scenarios/0-interactive-setup-choices.sh. As written it asked the installer to detect a private laptop and default to development, which the owner decision in STATBUS-465 (commit 054611d1d) reversed: the installer always suggests standalone. 3a87b058e (STATBUS-466) landed the questions and observed them with the real ./sb install on a PTY in a Linux container (tmp/statbus-466-observed/interactive-prompts.txt), stopping at Credentials because that sandbox has no database. No LXD-fleet scenario has driven those questions end to end in a hardened guest. Per doc/install-upgrade-testing.md, only a real run says whether they work there.

WHAT TO DO: add 0-interactive-setup-choices.sh on the LXD fleet, modelled on 0-interactive-admin-password.sh (expect on a PTY). Drive the Configuration questions with Enter at the mode, a domain whose first label is a country code, and Enter at the country name and code, then finish the install and assert .env.config and the running site.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 0-interactive-setup-choices.sh presses Enter at the mode question and observes standalone as the default, with all three modes explained
- [ ] #2 With a country-coded domain, the scenario presses Enter at the country name and code, observes the domain-derived suggestions, and the finished install has DEPLOYMENT_SLOT_NAME/DEPLOYMENT_SLOT_CODE set to that country, never StatBus/local
- [ ] #3 The install completes and the site passes its health and HTTPS checks; the observed prompts are recorded in this ticket
<!-- AC:END -->
