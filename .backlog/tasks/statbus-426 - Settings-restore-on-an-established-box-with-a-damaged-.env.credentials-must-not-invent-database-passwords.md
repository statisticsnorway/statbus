---
id: STATBUS-426
title: >-
  Settings restore on an established box with a damaged .env.credentials must
  not invent database passwords
status: In Progress
assignee: []
created_date: '2026-09-28 17:41'
updated_date: '2026-09-29 08:47'
labels:
  - install
dependencies: []
priority: medium
ordinal: 375200
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Found in review of the rc.16 installer fix (tmp/review-detect-env-2.md, -3.md). restoreSettingsBeforeDetect (cli/cmd/install.go) regenerates the generated .env when .env.config and .env.credentials exist and .env is missing. It checks that .env.credentials exists, not that it is complete. On an established box whose .env AND .env.credentials content were both damaged, loadOrGenerateCredentials fills missing keys with new random passwords/JWT secret, and the Services step then synchronises database role passwords to them. The intended case (an interrupted fresh install with a token-only credentials file, e.g. the upgrade arcs) needs that generation, so a blanket completeness refusal is wrong. Decide: distinguish an established box (DB volume exists / database answers) from a fresh one before generating secrets, and refuse with a plain operator remedy on an established box with incomplete credentials.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 An established box with a damaged .env.credentials is refused with a plain remedy, never given new database passwords
- [x] #2 An interrupted fresh install with a token-only .env.credentials still resumes
- [x] #3 Test for each case
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Audit after v2026.09.3 (2026-09-29): Still present in v2026.09.3 (install.go:3876 checks existence only). Schedule for the next candidate.

Implemented on branch fix/426-credentials, commit b36350c52 (own worktree $JCODE_SCRATCH_DIR/fix-426, never pushed). Design + evidence: tmp/fix-426.md. Guard lives in the single funnel config.loadOrGenerateCredentials, before any gen()/Save: missing/empty identity keys (4x POSTGRES_*_PASSWORD, JWT_SECRET) + existing statbus-<slot>-db-data volume => principled refusal (exit 78) naming file + missing key NAMES + restore remedy; volume absent => fresh resume generates; probe unanswerable => retriable error, never exit 78 (no daemon crash-loop; RestartPreventExitStatus=78 + STATBUS-307 park). classifyInstallFailure + install.sh allowlists extended and pinned by tests. Gates: gofmt/vet/shellcheck clean; cmd/config/compose/upgrade/install/dotenv suites green except 8 pre-existing 20GB-disk tests failing identically on origin/master.
<!-- SECTION:NOTES:END -->
