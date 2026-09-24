---
id: STATBUS-412
title: An operator revises every setup answer by running the installer again
status: To Do
assignee: []
created_date: '2026-09-24 16:05'
updated_date: '2026-09-24 18:44'
labels:
  - owner-decision
  - install
  - configuration
  - certificates
dependencies:
  - STATBUS-399
priority: high
type: enhancement
ordinal: 361200
---

## Status 2026-09-24

**To Do, owner decision.** #1-4 not met: `0-interactive-rerun-answers.sh` and `0-unattended-rerun-answers.sh` are absent, and `cli/cmd/install.go` still skips input for a present `.env.config`. **Remaining:** decide safe re-prompt semantics, then make every answer revisable on rerun without manual file edits, including cert choice and idempotent unattended behavior.

Baseline: `origin/master` at `373d15fc3`. Criterion disposition and remaining positive targets are above; the acceptance criteria below remain authoritative. An authored but unrun VM scenario is **proof pending**, not met.

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
An interactive rerun presents current installation mode, site address, display name, site code, and certificate choice as defaults and lets the operator revise each one. The unattended answers file provides the same five revisions. Unchanged answers produce a no-op, while changed answers update only affected settings and services and finish with the selected site's readiness check.

## Grounded evidence, 2026-09-24

Current configuration completion checks only whether `.env.config` exists, so reruns skip setup (`cli/cmd/install.go:974-977` at master `7a9cf707e`). Finland evidence records NXDOMAIN and certificate retry (`/Users/jhf/ssb/statbus/tmp/finland-answers-4.txt:1-12`) and says the private-certificate option was not prepared (`/Users/jhf/ssb/statbus/tmp/finland-chat-3.txt:27`). The reported browser error and 16:00 message are not present in the available evidence, so they remain undetermined. Private-certificate readiness depends on STATBUS-399.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 `new: test/install-recovery/scenarios/0-interactive-rerun-answers.sh` revises mode, site address, display name, site code, and certificate choice one at a time and observes each persisted value on the next rerun.
- [ ] #2 `new: test/install-recovery/scenarios/0-unattended-rerun-answers.sh` applies the same five revisions from the answers file and observes equivalent results.
- [ ] #3 `new: test/install-recovery/scenarios/0-interactive-rerun-answers.sh` accepts all current defaults and measures zero settings rewrites and zero unrelated service restarts.
- [ ] #4 `new: test/install-recovery/scenarios/0-interactive-rerun-answers.sh` changes site address and certificate choice, then observes trusted HTTPS at the new address through STATBUS-399 before success.
<!-- AC:END -->
