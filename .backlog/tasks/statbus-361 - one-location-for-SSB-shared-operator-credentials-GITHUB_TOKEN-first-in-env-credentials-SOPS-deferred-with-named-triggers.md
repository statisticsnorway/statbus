---
id: STATBUS-361
title: Every secret lives in .env.credentials; .env.config holds none
status: In Progress
assignee: []
created_date: '2026-09-07 13:48'
updated_date: '2026-10-16 14:02'
labels:
  - release-bug
  - ops
  - security
  - fleet
dependencies:
  - STATBUS-357
ordinal: 60
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
### North Star
Every secret StatBus uses lives in one place on each box, `.env.credentials`, and `.env.config` holds none, so settings can be shared, reviewed and copied without leaking a token.

### Zoom out
Almost all StatBus secrets are generated on the box and never leave it. A handful are shared operator values installed by hand: today `GITHUB_TOKEN` for dev (STATBUS-341: dev reads GitHub authenticated; `no` and `demo` stay anonymous), plus `SLACK_TOKEN` and `SEQ_API_KEY`. The rule: `.env.config` holds no secrets; every token, password or key lives in `.env.credentials` (mode 0600, untracked). Settings generation refuses a known secret name found in `.env.config`, and the installer moves legacy placements once on a rerun. `cloud.sh` never stores a secret; when it needs one for a box it reads that box's file over SSH, which is the trust boundary.

Owner ruling (2026-09-07): no encryption layer yet. SOPS+age is deferred until one of these holds: more than one SSB box needs a non-generated secret; STATBUS-358's approval service needs provisioned credentials; or a second person must operate the fleet and secrets start travelling through chat.

### Zoom in
- **Found, 2026-09-07:** dev had `SLACK_TOKEN` in both files and `SEQ_API_KEY` in `.env.config`; `GITHUB_TOKEN` was documented as a `.env.config` entry.
- **Shipped (v2026.09.3):** merge `c05b3ccf6` and `f7b84a5d5`, `31e4e5f37`, `626bc0d9b`, `c514d4264`, `f8503adca`. The readers take the three tokens from `.env.credentials` (a non-empty process environment value wins). The upgrade service loads them at startup without a systemd `EnvironmentFile`. `./sb config generate` refuses a misplaced secret and points to `./sb install`, and install reruns migrate legacy lines once, removing duplicates. `SEQ_API_KEY` keeps a placeholder because `docker-compose.app.yml` requires it.
- **Proof, unit:** `TestConfigRejectsMisplacedSecrets_STATBUS361`, `TestLegacySecretsMigrateOnce_STATBUS361`, `TestPlainGenerateRejectsFreshSecret_STATBUS361` (`cli/internal/config`); `TestInstallerFreshMisplacedSecretRejected_STATBUS361`, `TestInstallerRerunMigratesDuplicatesOnce_STATBUS361`, `TestStandaloneGenerateLegacyPointsToInstall_STATBUS361` (`cli/cmd/install_credentials_test.go`). Green 2026-10-15.
- **Proof, real box:** smoke `0-happy-upgrade` (`36505292818`) upgraded a v2026.09.2 configuration with placeholder tokens.
- **Not observed:** on dev itself, that no secret remains in `.env.config` and that the upgrade service's GitHub calls are authenticated (5000/h). Both need SSH to dev. The planned "Where credentials live" paragraph in `doc/CLOUD.md` does not exist.

### Closing review
- **Memory:** none needed.
- **Documentation:** the `doc/CLOUD.md` paragraph is still to write.
- **Cleanup:** none.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 On dev, `grep -E '^(GITHUB_TOKEN|SLACK_TOKEN|SEQ_API_KEY)=' .env.config` prints nothing, and the same keys are set in `.env.credentials`
- [x] #2 Settings generation exits non-zero naming the key and the file it belongs in when a secret is in `.env.config`, and install reruns migrate legacy placements once (`TestConfigRejectsMisplacedSecrets_STATBUS361`, `TestLegacySecretsMigrateOnce_STATBUS361`, `TestInstallerRerunMigratesDuplicatesOnce_STATBUS361`)
- [x] #3 STATBUS-341's tests pass with the token read from `.env.credentials`
- [ ] #4 Dev's upgrade service makes authenticated GitHub calls (5000/h); `no` and `demo` stay anonymous
- [x] #5 `doc/CLOUD.md` has a "Where credentials live" paragraph with the rule and the table of values
- [ ] #6 [Owner] Put a fine-grained read-only GITHUB_TOKEN in .env.credentials on dev and demo (STATBUS-341 ruling); the agent then observes AC4
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
### Evidence
- **AC2-3:** green locally on master, 2026-10-15; in Go Test since v2026.09.3.
- **AC1, AC4:** open; need a read on dev.
- **AC5:** open; `rg -i "where credentials live" doc/CLOUD.md` finds nothing.
- **History:** the 2026-09-07 to 09-25 implementation, review and sequencing notes are in Git history.

### Read on dev (2026-10-16 14:00, read-only, key names only, delegated per AC6)
- **AC1 holds:** `.env.config` contains none of GITHUB_TOKEN, SLACK_TOKEN, SEQ_API_KEY. In `.env.credentials` (0600), SLACK_TOKEN and SEQ_API_KEY are set and **GITHUB_TOKEN is absent**.
- **demo:** the same. No secret in `.env.config`, and GITHUB_TOKEN is absent from `.env.credentials`. `no` was not read (the agent has no SSH to statbus_no).
- **AC4 does not hold:** dev's upgrade service runs anonymously. Its egress IP shows the anonymous core budget (limit 60). The STATBUS-341 ruling (2026-09-03) gives dev and demo the token. It was never installed, or it was lost.
- **AC5 done:** `doc/CLOUD.md` has a "Where credentials live" section with the rule and the table. The standalone step 4, which told operators to put SEQ_API_KEY/SLACK_TOKEN in `.env.config` (which generation now refuses), now points to `.env.credentials`.
- **AC6 reworded:** what remains for the owner is to put a fine-grained read-only GITHUB_TOKEN into dev's and demo's `.env.credentials`. An agent cannot make a secret. After that, the agent observes AC4 (`curl https://api.github.com/rate_limit` with the token reports limit 5000, and the upgrade service's next discovery succeeds).
<!-- SECTION:NOTES:END -->
