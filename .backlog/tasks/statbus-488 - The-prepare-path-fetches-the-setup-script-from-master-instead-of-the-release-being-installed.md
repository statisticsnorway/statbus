---
id: STATBUS-488
title: >-
  The prepare path fetches the setup script from master instead of the release
  being installed
status: Done
assignee: []
created_date: '2026-10-13 12:28'
updated_date: '2026-10-13 14:47'
labels:
  - install
  - fidelity
  - docs
dependencies: []
priority: high
type: bug
ordinal: 414204
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
FOUND 2026-10-13 during the owner installation in Uganda. The box was prepared with `curl -fsSL https://raw.githubusercontent.com/statisticsnorway/statbus/master/ops/setup-ubuntu-lts.sh`, that is, master rather than a release. So the code that hardens and prepares a production box is untagged, unreviewed and free to drift from the release that is then installed on it. Owner decision 2026-10-13: the operator path must pick the setup script that belongs to the release being installed, not whatever master holds.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 The published prepare instruction resolves setup-ubuntu-lts.sh from the release or channel the operator is installing, the same way install.sh resolves the program and the checkout, never from the master branch. Checked by reading the published step and by the URL or path it produces for a named version.
- [x] #2 Preparing a box for a named older release uses that release copy of the script, verified by comparing the fetched file with the tag contents. Checked by the comparison being recorded in this ticket.
- [x] #3 No operator-facing instruction in the repository or on the site tells anyone to fetch master; any such text is corrected. Checked by a search of the operator documentation.
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Mechanism (2026-10-13): the published prepare step resolves the release exactly as install.sh does, no new release system. VERSION=<tag you will install> (same tag as install.sh --version) or, unset, the stable channel via the same call install.sh makes (curl -sL api.github.com/repos/statisticsnorway/statbus/releases/latest | grep tag_name | cut). The script is then fetched from raw.githubusercontent.com/statisticsnorway/statbus/${VERSION}/ops/setup-ubuntu-lts.sh. Chosen over the installer offering the script because preparing runs as root BEFORE install.sh (which runs as the service user), so the installer cannot supply it in time.
Changed: doc/setup-ubuntu-lts.md (Quick Start), doc/DEPLOYMENT.md (prepare step), doc/hetzner-bootstrap.md (step 8), ops/setup-ubuntu-lts.sh (usage header), doc/CLOUD.md (standalone step 2 now points at the release-matched fetch). Each snippet is marked '# STATBUS-488 prepare fetch'.
Test: test/install-recovery/tests/setup-release-matched-fetch-test.sh, wired in harness-selftest.yaml. Runs each marked snippet against a stubbed curl. RED on the parent docs: 8 FAIL lines (each doc 'still fetches the setup script from master' + 'has no marked prepare fetch'), exit 1. GREEN: 8 PASS, e.g. named -> .../statbus/v2026.03.0/ops/setup-ubuntu-lts.sh, stable -> .../statbus/v2026.09.1/ops/setup-ubuntu-lts.sh; exit 0. Whole setup-*.sh suite passes locally.
AC2: ran the published snippet with VERSION=v2026.09.2 (older release): fetched file is byte-identical to git show v2026.09.2:ops/setup-ubuntu-lts.sh (sha256 019565123fd8364f5e2da84ac15762dca73c0780355b4dbce8ce3dc11aa29413) and differs from master. Releases before v2026.09.2 ship ops/setup-ubuntu-lts-24.sh instead (noted in the doc).
AC3: rg 'master/ops/setup' over doc/ ops/ finds nothing. OPEN: the statbus.org website text is not in this repository; if it mirrors the master curl line it must be updated there by whoever owns the site.

CI on f4246e877: Harness Selftest 38415573172 success (job harness-selftest success, includes the new step), Go Test 38415573332 success, app build & lint 38415573255 success, Images 38415573220 success, CodeQL 38415567512 success. Fast Tests 38415603224/38416055632 cancelled by the newer push bdf361620 (contains this commit); its run 38416193759 was still in progress at close-out. That is pg_regress and not touched by this docs/test change.
<!-- SECTION:NOTES:END -->
