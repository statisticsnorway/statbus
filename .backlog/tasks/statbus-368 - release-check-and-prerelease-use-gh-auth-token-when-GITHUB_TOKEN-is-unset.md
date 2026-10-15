---
id: STATBUS-368
title: >-
  The release gate reads GitHub as the person running it and says which identity
  it used
status: In Progress
assignee: []
created_date: '2026-09-14 11:41'
updated_date: '2026-10-15 20:09'
labels:
  - release-bug
  - release
  - cli
dependencies:
  - STATBUS-370
priority: medium
type: bug
ordinal: 20
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
### North Star
The release gate reads GitHub as the person running it, and says which identity it used, so a rate limit can never look like a CI failure.

### Zoom out
Developers here log in with `gh auth login`; nobody exports `GITHUB_TOKEN`. A gate that only knows `GITHUB_TOKEN` therefore reads GitHub anonymously, sharing 60 requests per hour with everything else on that address, and its 403s look like broken CI. The cure is one resolver for every GitHub read in the release code, in a fixed order: `GITHUB_TOKEN`, then `gh auth token`, then anonymous. The gate prints which one it chose, and a 403 while anonymous names `gh auth login` as the fix. The token must never leak into Git argv, logs or diagnostic files. Container-registry probes deliberately stay anonymous, so a privately readable image can never pass the public-deployability check.

### Zoom in
- **Incident, 2026-09-14:** polling `./sb release check` every 30 s hit HTTP 403 after about 20 minutes, and the gate reported all three workflow checks as "GitHub API error HTTP 403". `githubAuthHeader()` (`cli/internal/release/check.go`) sent a token only when `GITHUB_TOKEN` was set.
- **Shipped (v2026.09.3):** `baf6f64fb` adds `cli/internal/release/github_auth.go` (modes "authenticated via GITHUB_TOKEN", "authenticated via gh auth", "anonymous, 60/h"); all release HTTP reads use it, and Git `ls-remote`/`fetch` carry the token as an extraheader in the environment, not argv. `0aa5a982f`, `1e96d380f` and `6442f2b8a` redact the token, its base64 forms and every Authorization header from errors, logs and diagnostics. STATBUS-379 was the narrower duplicate, closed as superseded.
- **Proof, unit:** `TestGitHubAuthPrecedenceAndFallback`, `TestGitHubGitEnvUsesExtraHeaderNotArgv`, `TestGitHubGitEnvResetsInheritedAuthorizationBeforeAddingItsOwn`, `TestAuthenticatedGitFailureRedactsCredentialsBeforeErrorsLogsAndDiagnostics`, `TestCommandOutputRedactsGitStderr` (`cli/internal/release/github_auth_test.go`), green 2026-10-15.
- **Observed 2026-10-15:** on a machine with `gh auth login` and no `GITHUB_TOKEN`, `./sb release check` printed `(GitHub: authenticated via gh auth)` and every GitHub-reading gate answered (`tmp/vet/368-release-check.log`). Its red lines were unrelated, about uncommitted migrations in the shared checkout.

### Closing review
- **Memory:** none needed.
- **Documentation:** none needed; the gate prints its identity.
- **Cleanup:** none.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Every GitHub read in the release code resolves its token as `GITHUB_TOKEN`, then `gh auth token`, then anonymous (`TestGitHubAuthPrecedenceAndFallback`)
- [x] #2 The gate prints which identity it used; on a machine with only `gh auth login` it says "authenticated via gh auth" (observed 2026-10-15)
- [x] #3 The token never appears in Git argv, errors, logs or diagnostic files (`TestGitHubGitEnvUsesExtraHeaderNotArgv`, `TestAuthenticatedGitFailureRedactsCredentialsBeforeErrorsLogsAndDiagnostics`, `TestCommandOutputRedactsGitStderr`)
- [ ] #4 [Owner] Accept the single observed authenticated run in place of the original 100 consecutive runs, and record it in Implementation Notes; then set Done. Not accepted: add the 100-run observation as a new criterion.
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
### Evidence
- **AC1, AC3:** green locally on master, 2026-10-15.
- **AC2:** `env -u GITHUB_TOKEN ./sb release check` on the owner's workstation, 2026-10-15, line 7: `(GitHub: authenticated via gh auth)`.
- **History:** the 2026-09-14 build-and-hold notes, batch sequencing and 09-22/23 implementation notes are in Git history.
<!-- SECTION:NOTES:END -->
