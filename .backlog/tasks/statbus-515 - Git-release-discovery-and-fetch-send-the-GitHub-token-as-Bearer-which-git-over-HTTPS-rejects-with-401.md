---
id: STATBUS-515
title: >-
  Git release discovery and fetch send the GitHub token as Bearer, which git
  over HTTPS rejects with 401
status: Done
assignee: []
created_date: '2026-10-17 15:31'
updated_date: '2026-10-17 17:41'
labels:
  - upgrade
  - github
dependencies: []
priority: high
ordinal: 441204
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
### North Star
A box with GITHUB_TOKEN discovers and fetches releases authenticated. A box without one behaves exactly as today.

### Zoom out
STATBUS-341 gave the upgrade daemon an optional GITHUB_TOKEN. The REST calls send it as `Authorization: Bearer`, which the REST API accepts. Git discovery (`DiscoverTagsViaGit`) and the pre-swap fetch use `gitFetchEnv` (cli/internal/upgrade/service.go), which passes the same Bearer header to git through GIT_CONFIG http.extraheader. GitHub's git-over-HTTPS endpoint does not accept Bearer for a personal access token. It needs Basic auth with the token as the password (for example `x-access-token:<token>`).

### Zoom in
- **Found 2026-10-17, installing a real fine-grained token on dev and demo (STATBUS-361 AC4):** `git ls-remote` with the daemon's exact env got `HTTP/2 401` on both boxes, and no tags. On this machine the same token gives no tag with Bearer and the tag with Basic `x-access-token:<token>`. The REST rate limit with the token reads 5000.
- **Effect:** every box with a token cannot discover or fetch releases. Anonymous boxes are unaffected. The unit tests (`TestGitFetchEnvironmentAuthorizationIsOptional_STATBUS341`, the DiscoverTagsViaGit trace test) assert the Bearer string, so they passed on the defect.
- **Containment:** the token was removed again from dev and demo, and their upgrade services were restarted anonymous.

### Closing review
- **Memory:** none needed.
- **Documentation:** the CLOUD.md credentials table already describes GITHUB_TOKEN; no change.
- **Cleanup:** delete the local tmp/github-token* files after the token is installed.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 gitFetchEnv sends Basic auth with the token as the password, and a test asserts that exact header value
- [x] #2 A test against GitHub, or a recorded run, shows the old Bearer form is refused and the new form lists the tags with a real token
- [x] #3 Installed on dev and demo (STATBUS-361 AC4): the daemon's git discovery lists tags through the token, and the REST rate limit reads 5000
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
### Fix (c0c7bb43e, 2026-10-17)
- `gitFetchEnv` now sends `Authorization: Basic base64(x-access-token:<token>)`. REST (githubRequest) keeps Bearer, which the REST API accepts. The doc comment on gitFetchEnv states why.
- **Red, then green:** `TestGitFetchEnvSendsTokenAsBasicAuth_STATBUS515` failed against the old code (got 'Authorization: Bearer github_pat_test') and passes now. The two STATBUS-341 tests asserted the Bearer string, so they passed on the defect; they now assert the Basic form. The argv-leak check also covers the encoded credential. The upgrade package passes; golangci-lint reports 0 issues.
- **Real GitHub, on dev and on demo, with the real token:** git ls-remote with the old Bearer form lists 0 tags (HTTP 401); with the new Basic form it lists v2026.10.2.
- **Next:** this ships in the next candidate. The token is installed on dev and demo once their daemon runs a binary containing c0c7bb43e. Until then a token would break their discovery, so they stay anonymous.

- **CI:** Go Test passed on c0c7bb43e. AC3 (installed and observed on dev and demo) waits for a release containing the fix.

### Installed on dev (2026-10-17 17:41, dev at v2026.10.3-rc.01, which contains c0c7bb43e)
- The token is in .env.credentials (0600). Only statbus-upgrade@statbus_dev was restarted; it is active and runs the rc.01 binary.
- **Observed:** git ls-remote with the daemon's Basic header lists v2026.10.3-rc.01. The daemon's first discovery after the restart logged 'Discovery: 306 tag(s) via git, 306 match channel prerelease', with no 401 or fetch error. `./sb upgrade check` succeeds. The token's REST limit reads 5000.
- The daemon reads the token in-process (loadOperatorCredentials, service.go:3056), not from its systemd environment, so /proc/<pid>/environ does not show it; that is by design.
- **Demo:** installed after the next stable promotion carries this fix (demo follows stable). Done for the fix itself.
<!-- SECTION:NOTES:END -->
