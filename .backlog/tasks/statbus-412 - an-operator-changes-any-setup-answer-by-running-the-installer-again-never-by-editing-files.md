---
id: STATBUS-412
title: An operator changes any setup answer by running the installer again, never by editing files
status: To Do
assignee: []
created_date: '2026-09-24 16:05'
labels:
  - install
  - configuration
  - certificates
dependencies: []
references:
  - /Users/jhf/ssb/statbus/tmp/finland-answers-4.txt
  - /Users/jhf/ssb/statbus/tmp/finland-chat-3.txt
priority: high
type: enhancement
ordinal: 361200
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
On any interactive rerun, the installer offers the operator a way to change each setup answer, including installation mode, site address, display name, site code, and certificate choice. It presents current values as defaults so an unchanged rerun stays unchanged. The unattended path accepts equivalent changes through its answers file. After an answer changes, installation applies the affected settings and services, obtains the chosen certificate, and checks that the site works. Operators do not have to edit configuration files by hand.

## Grounded evidence

At master `7a9cf707e`, `cli/cmd/install.go:974-977` implements `checkConfigDone` by testing only for `.env.config` existence. Therefore the setup step is skipped on reruns with that file present; this check cannot notice an operator's wish to change an answer. `/Users/jhf/ssb/statbus/tmp/finland-chat-3.txt:27` records that the private-certificate option was not prepared in the installer. `/Users/jhf/ssb/statbus/tmp/finland-answers-4.txt:1-12` contains the web-entry-point log from 17:22: certificate issuance for `statbus.statfin.eu` failed because public DNS returned NXDOMAIN and issuance retried after 600 seconds. The claimed browser text `SSL_ERROR_INTERNAL_ERROR_ALERT` and a 16:00 customer message were **not found** in the available copy of that evidence file, so the exact browser error and timestamp are not determined here.

STATBUS-389 covers choosing a workable mode and explaining the network situation during setup. STATBUS-399 covers the private-certificate choice and trust instructions. This ticket covers revisiting and changing answers on a later run, independently of those implementations.

## Proving scenarios

**New** isolated install-recovery harness case: finish a standalone installation with a test certificate choice, rerun the published one install command interactively, change only the certificate choice to private, and assert that HTTPS presents a certificate issued by the local authority. Assert that unchanged answers retain their values and do not needlessly restart unaffected services. A second **new** unattended case changes the same choice in the answers file and observes the same result. Use an isolated disposable VM and test domain, not the Finland box.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 An interactive rerun offers to revise mode, address, display name, site code, and certificate choice, shows current values as defaults, and accepts an unchanged choice without rewriting settled configuration.
- [ ] #2 An unattended rerun reads changed values from the answers file and applies them without requiring manual edits to generated files.
- [ ] #3 When a setup answer changes, the installer regenerates affected settings, restarts only affected services, and confirms readiness before announcing success.
- [ ] #4 The new isolated standalone rerun scenario changes the certificate choice to private and HTTPS presents a local-authority certificate; the unchanged-answer rerun leaves unrelated services alone.
<!-- AC:END -->
