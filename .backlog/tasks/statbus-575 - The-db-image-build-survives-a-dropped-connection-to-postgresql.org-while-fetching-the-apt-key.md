---
id: STATBUS-575
title: >-
  The db image build survives a dropped connection to postgresql.org while
  fetching the apt key
status: In Progress
assignee: []
created_date: '2026-11-07T18:12:00Z'
updated_date: '2026-11-07T20:00:00Z'
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
- [ ] #2 A local docker build of the db stage succeeds, and a build with the key URL unreachable fails with a clear message naming the URL
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
2026-11-07: In Progress, fixed test-first. RED c398e79f9 reproduces partial-response/HTTP/unreachable failures against the Dockerfile's actual RUN command. GREEN e8bd3d53d downloads to a temporary file with fail-on-HTTP, bounded retries and explicit URL diagnostics before GnuPG imports it. No TLS or signing verification bypass. Actual Docker ppa/base builds passed, including partial-key then HTTP503 then success with byte-identical keyring, and unreachable URL fails within its budget. Evidence: tmp/575-{red,green,docker-base,docker-transient,docker-unreachable}.log, tmp/575-worker-journal.md. Coordinator independently runs postgres/test_key_download.py. Permanent Harness Selftest coverage committed 0b4e3ff89. Exact-SHA CI and next candidate gate still pending, so ticket remains In Progress.

Acceptance precision: the local successful build exercised ppa/base (repository key, signed apt update and PostgreSQL server packages), not the full pg-runtime extension image. Leave AC2 unchecked until the full db-image build is verified; the unreachable ppa build and partial-response fixture are already verified.
<!-- SECTION:NOTES:END -->
