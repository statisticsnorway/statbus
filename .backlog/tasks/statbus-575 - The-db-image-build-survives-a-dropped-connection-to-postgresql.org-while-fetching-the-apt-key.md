---
id: STATBUS-575
title: >-
  The db image build survives a dropped connection to postgresql.org while
  fetching the apt key
status: Done
assignee: []
created_date: '2026-11-07T18:12:00Z'
updated_date: '2026-11-07T20:48:00Z'
labels:
  - build
  - ci
dependencies: []
type: bug
ordinal: 502204
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
The statbus-db image build downloads the PostgreSQL apt signing key with `curl -sSL https://www.postgresql.org/media/keys/ACCC4CF8.asc | gpg --dearmor` (postgres/Dockerfile). There is no --fail and no --retry, so one dropped connection to postgresql.org fails the whole build, and an HTTP error page would be piped into gpg.

Seen 2026-11-07: v2026.11.2-rc.02 Test Hardening 42399643767, install-stack built the db image in the guest; curl reported "OpenSSL SSL_read: unexpected eof" after 85 s and gpg got no data. The same URL timed out once in three tries from the Mac at 18:11.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 postgres/Dockerfile fetches the key with curl --fail and bounded retries (or the key is vendored with its fingerprint checked), so an error page or a dropped connection never reaches gpg
- [x] #2 A local docker build of the db stage succeeds, and a build with the key URL unreachable fails with a clear message naming the URL
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
2026-11-07: In Progress, fixed test-first. RED c398e79f9 reproduces partial-response/HTTP/unreachable failures against the Dockerfile's actual RUN command. GREEN e8bd3d53d downloads to a temporary file with fail-on-HTTP, bounded retries and explicit URL diagnostics before GnuPG imports it. No TLS or signing verification bypass. Actual Docker ppa/base builds passed, including partial-key then HTTP503 then success with byte-identical keyring, and unreachable URL fails within its budget. Evidence: tmp/575-{red,green,docker-base,docker-transient,docker-unreachable}.log, tmp/575-worker-journal.md. Coordinator independently runs postgres/test_key_download.py. Permanent Harness Selftest coverage committed 0b4e3ff89. Exact-SHA CI and next candidate gate still pending, so ticket remains In Progress.

Acceptance precision: the local successful build exercised ppa/base (repository key, signed apt update and PostgreSQL server packages), not the full pg-runtime extension image. Leave AC2 unchecked until the full db-image build is verified; the unreachable ppa build and partial-response fixture are already verified.

2026-11-07 20:07 UTC: full local pg-runtime Docker build now passed, exit0 in386.9s, image sha256:6cc164a7d557bcfc68cf9ea94737847d19ca819027575f9ee71e294995d4dc54. This includes all runtime extensions, not just ppa/base. Log tmp/575-docker-runtime.log. Together with the unreachable-URL failure and partial/503 recovery builds, AC2 is now verified. Coordinator independently reran all4 fault tests green in41.3s. Await exact-SHA CI and candidate gates before Done.

2026-11-07 20:48 UTC: verified on published candidate v2026.11.2-rc.03 at cb962d0a8be4aba086ffc7b44013e5875a633e9d. Exact-SHA Test Hardening42411888040 completed/success, all three jobs bootstrap-script, install-stack and setup-script-service-account successful. Its actual install-stack database-image build executed the corrected PostgreSQL-key RUN instruction at20:37:49Z: curl --fail, retry3/all-errors and bounded timeouts into a temporary file, then gpg --dearmor. Complete log tmp/rc03-hardening.log line1375, explicit job verdicts tmp/rc03-hardening-verdict.json. Candidate Test Smoke42411993194 completed/success for real LXD fresh-install and stable-v2026.11.1-to-candidate happy-upgrade workflows; log tmp/rc03-smoke.log. Published Release42411887899 completed/success with all9assets. This supplements the previously verified full local pg-runtime image, unreachable-URL bounded failure, partial/HTTP503 recovery, byte-identical keyring and four coordinator fault tests. Exact-SHA Harness42410614684, Images42410614678, Go42410614674, App42410614676 and Fast42410876430 also completed/success. Both ticket acceptance criteria are verified, including actual candidate install behavior. The wider recovery-fleet/arc release gate continues separately and is not being claimed complete here.
<!-- SECTION:NOTES:END -->
