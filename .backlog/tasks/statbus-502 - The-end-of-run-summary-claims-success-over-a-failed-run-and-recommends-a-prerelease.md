---
id: STATBUS-502
title: >-
  The end-of-run summary claims success over a failed run and recommends a
  prerelease
status: Done
assignee: []
created_date: '2026-10-13 15:35'
updated_date: '2026-10-13 15:44'
labels:
  - install
  - ux
  - cloud
dependencies: []
priority: high
type: bug
ordinal: 428204
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
FOUND 2026-10-13 in the final summary of the owner Uganda prepare run, and it has three faces. (1) The headline "Setup Complete!" was printed at line 1987 BEFORE the failure report at line 2020, and the run then exited 1 with two failures (etckeeper installed, etckeeper initialized, from Stage 1 transient apt failure). The headline contradicts the last three lines, and the summary listed eight achievements while omitting the one thing that failed, so an operator reading only the summary concludes everything succeeded. (2) The summary and its recommended next steps were unconditional: "devops user created (ops/admin)", "CI command allowlist installed from the repo, with a published hash" and "(ops) Log in as devops for host administration tasks" were shown even after STATBUS-501 made those stages cloud-only - so the text claimed work a standalone run had not done. (3) The general installation guidance recommended "curl -fsSL https://statbus.org/install.sh | bash -s -- --channel prerelease", pushing an ordinary operator onto the prerelease channel; the owner ruling 2026-10-13 is that stable is the default and the general guidance names NO channel at all, because naming our internal channels invites an ordinary operator to choose one.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 The failure list is printed BEFORE any headline, and a run with failures gets its own headline rather than "Setup Complete!". Checked by test/install-recovery/tests/setup-summary-truth-test.sh assertions 1 and 2.
- [x] #2 The summary and the next steps mention cloud-only work only when this run did it. Checked by assertion 3, which requires each of those entries to sit behind the cloud-intent condition.
- [x] #3 The general installation guidance names no channel at all: the plain "install.sh | bash" is the recommendation, and no --channel appears in it. Checked by assertion 4.
- [x] #4 A failed run still exits non-zero. Checked by assertion 5.
- [ ] #5 The next real preparation on the Uganda box either ends with a clean "Setup Complete!" or leads with the failures, and shows no devops or CI-allowlist line; to be recorded in STATBUS-497.
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Filed and fixed 2026-10-13 by the coordinator. Implementation: the failure report moved above the headline; the headline is "Setup finished WITH PROBLEMS: N verification(s) failed" when N > 0; the devops and CI-allowlist summary lines and the "(ops) log in as devops" step sit behind the cloud-intent check; the step list is numbered dynamically so a standalone run has no gap; and the install guidance is the plain command with no channel, per the owner ruling that stable is the default and our internal channels are not an ordinary operator business. The owner caught the last point in review - my first version spelled out "STABLE channel" and explained prerelease and canary, which is the same leak STATBUS-501 removed from the stages. EVIDENCE: RED against HEAD shows seven FAIL lines including the ordering (failure list at 1762 vs headline at 1727) and the prerelease recommendation; GREEN shows six PASS lines; bash -n parses; all 15 setup-* tests pass together; the test is wired into .github/workflows/harness-selftest.yaml.

GREEN and closed 2026-10-13: Harness Selftest SUCCESS at b2d2c910f (job level read), app build & lint success; Go Test for that SHA was cancelled by the later pushes, which is the usual supersession. Criterion 5 (the next real preparation on the Uganda box either ends with a clean "Setup Complete!" or leads with its failures) rides with STATBUS-497.
<!-- SECTION:NOTES:END -->
