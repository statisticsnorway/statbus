---
id: STATBUS-376
title: A third-party operator installs a ready StatBus site on Ubuntu 26.04 from the published instructions
status: To Do
assignee: []
created_date: '2026-09-18 17:48'
updated_date: '2026-09-24 18:47'
labels:
  - release-bug
  - install
  - setup
  - ubuntu
  - third-party
  - release
  - fail-fast
dependencies:
  - STATBUS-384
  - STATBUS-385
  - STATBUS-386
  - STATBUS-387
  - STATBUS-388
  - STATBUS-389
  - STATBUS-390
  - STATBUS-391
  - STATBUS-392
  - STATBUS-393
  - STATBUS-394
  - STATBUS-400
  - STATBUS-401
  - STATBUS-402
  - STATBUS-403
  - STATBUS-404
  - STATBUS-405
  - STATBUS-406
  - STATBUS-407
  - STATBUS-408
  - STATBUS-409
  - STATBUS-410
  - STATBUS-411
  - STATBUS-412
priority: high
type: bug
ordinal: 1
---

## Status 2026-09-24

**To Do:** #1-10 not met as written: seven `test/setup/public-setup-*` tests and the umbrella `0-third-party-ubuntu-26-04-install.sh` are absent. `373d15fc3` improved the installer but does not prove the independent published-instructions Ubuntu 26.04 workflow. **Remaining:** implement D1-D7 public setup, test operator-only installation and interruption, and record candidate-tag VM service/HTTPS evidence.

Baseline: `origin/master` at `373d15fc3`. Criterion disposition and remaining positive targets are above; the acceptance criteria below remain authoritative. An authored but unrun VM scenario is **proof pending**, not met.

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
A third-party operator starts with a fresh Ubuntu 26.04 host, follows the published setup and one-command installation instructions, and reaches a ready site without Statistics Norway fleet knowledge. The public setup creates only the StatBus service account and public prerequisites. The installer supplies one recovery path, creates the first administrator privately, verifies every required service, and proves the advertised endpoint before printing success.

## Dated evidence, 2026-09-24

The Finland install refused 85 GB free space and printed a directory-dependent recovery command (`/Users/jhf/ssb/statbus/tmp/finland-transcript-actual.txt:14-36`). Port 80 then prevented the web entry point from starting, but a rerun accepted database health and migrations later failed through `127.0.0.1:5431` (`/Users/jhf/ssb/statbus/tmp/finland-transcript-actual.txt:67-80,121-147`). Step 15 failed without `.users.yml` and later exposed a password-bearing result column (`/Users/jhf/ssb/statbus/tmp/finland-transcript-2-actual.txt:53-65,99-112`). The automatic-update service remained activating while output called it not running (`/Users/jhf/ssb/statbus/tmp/finland-transcript-2-actual.txt:114-169`).

The customer's API log proves authenticator password failure (`/Users/jhf/ssb/statbus/tmp/finland-answers-4.txt:52-58`). A surviving database volume with regenerated settings can cause that split on a disposable VM (`/Users/jhf/ssb/.jcode/scratch/rest-loop.md:45-58`), but how the customer credentials diverged is undetermined (`/Users/jhf/ssb/.jcode/scratch/rest-loop.md:16-18`). The normal local replay did not reproduce the API loop (`/Users/jhf/ssb/statbus/tmp/local-ville-replay.md:984-987`). It did reproduce the web-entry-point `Created` state and route timeout (`/Users/jhf/ssb/statbus/tmp/local-ville-replay.md:697-783,989-992`) and a success message before the advertised HTTPS endpoint completed TLS (`/Users/jhf/ssb/statbus/tmp/local-ville-replay.md:598-605,643-695`). Successful installation normally records completion in `public.upgrade` (`cli/cmd/install.go:2938-3039` at master `7a9cf707e`).

Current public setup still contains centralized authorized-key handling and fleet-labelled stages (`ops/setup-ubuntu-lts.sh:162-286,297-322,1647-1654,1703` at master `7a9cf707e`). These source anchors define the D1-D7 separation target. Unsupported historical commit, CI, and broad evidence-corpus assertions are withdrawn.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 `new: test/setup/public-setup-key-source-test.sh` proves D1 with a valid public key source and a plain refusal for an unavailable configured source.
- [ ] #2 `new: test/setup/public-setup-key-preflight-test.sh` proves D2 by refusing before account creation when the service account would receive zero authorized keys, and by accepting both pasted and file or environment key input.
- [ ] #3 `new: test/setup/public-setup-openssh-test.sh` proves D3 by installing and starting `openssh-server` before hardening and verification.
- [ ] #4 `new: test/setup/public-setup-os-version-test.sh` proves D4 by accepting Ubuntu 24.04 and 26.04 and refusing unsupported releases before mutation.
- [ ] #5 `new: test/setup/public-setup-prompt-test.sh` proves D5 with a plain explanation of every requested identity and key input.
- [ ] #6 `new: test/setup/public-setup-boundary-test.sh` proves D6 by keeping `devops`, GitHub key retrieval, and `SSHDOERS_REF` in the named fleet layer while public setup output contains only public concepts.
- [ ] #7 `new: test/setup/public-setup-summary-test.sh` proves D7 by deriving every summary line from observed stage results, including skipped and failed stages.
- [ ] #8 `new: test/install-recovery/scenarios/0-third-party-ubuntu-26-04-install.sh` is the umbrella third-party run. It executes public setup, the published install command, private administrator creation, and a rerun from an interrupted point, then observes every required service ready.
- [ ] #9 `new: test/install-recovery/scenarios/0-third-party-ubuntu-26-04-install.sh` selects an HTTPS trust mode, completes a trusted TLS handshake and HTTP response at the advertised address, and only then observes the success text.
- [ ] #10 `new: test/install-recovery/scenarios/0-third-party-ubuntu-26-04-install.sh` run `STATBUS-376-third-party-ubuntu-26-04-1` verifies `new: test/install-recovery/evidence/STATBUS-376-third-party-ubuntu-26-04-1.md` records the candidate tag, VM architecture, Ubuntu image, D1-D7 test results, service states, HTTPS result, and operator transcript.
<!-- AC:END -->
