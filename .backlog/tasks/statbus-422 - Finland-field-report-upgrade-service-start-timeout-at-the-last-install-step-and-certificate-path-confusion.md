---
id: STATBUS-422
title: >-
  Finland field report: upgrade-service start timeout at the last install step,
  and certificate path confusion
status: In Progress
assignee: []
created_date: '2026-09-27 10:07'
updated_date: '2026-10-08 11:57'
labels:
  - installer
dependencies: []
priority: high
ordinal: 371200
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Ville-Mattis Pilvio, 2026-09-25 (v2026.09.2 era). Owner asked to capture for discussion on his return.
## The report (Ville, 2026-09-25, v2026.09.2-era binary)

Fresh install on statbus.statfin.eu. Steps 1-16 all green; step 17 failed:

```
[17/17] Upgrade service      RUNNING
  Unit statbus-upgrade@statbus.service is in failed state — running reset-failed
  Enabling and starting statbus-upgrade@statbus.service
Job ... failed because a timeout was exceeded.
[17/17] Upgrade service      FAILED: enable service: exit status 1
INVARIANT FAILED_INSTALL_HAS_AUDIT_TRAIL violated (audit-only): install failed with no upgrade row (detectedState=db-unreachable) ...
```

Ville's own guess: "I needed to remove a service beforehand" (a leftover failed unit from a previous attempt).

## Defects/questions this exposes (for owner discussion)

1. **Step 17 robustness:** a previously failed unit gets reset-failed but the start still timed out. The installer needs the unit's actual journal in the failure output (the log says "See systemctl status" — the operator gets no cause), and the start must tolerate/clean a wedged prior unit. What timed out — the service's first-boot work (config generate, recovery scan) exceeding TimeoutStartSec?
2. **detectedState=db-unreachable is wrong-looking:** the DB was healthy at step 8 (services all healthy) yet the audit invariant classified db-unreachable. Audit-only, but the classification deserves a look.
3. **Certificate path confusion:** his .env.config has `TLS_CERT_FILE=/home/statbus/statbus.crt` — HOST paths. The documented values are CONTAINER paths (/data/custom-certs/...). The installer/config should validate that the cert files exist at the container path and print the mapping expectation, instead of failing later and mysteriously.
4. **Legacy placeholder placement:** his .env.config carries SEQ_API_KEY/SLACK_TOKEN placeholder values — exactly what STATBUS-361 migrates. His box is the migration's target case; the rc.07-era crash-loop fix (service-side migration) covers the upgrade path.
5. He had to hand-add SITE_DOMAIN to .env.config — worth checking whether the flow told him to (the FRESH refusal leaves the documented file to edit — did the guidance reach him?).

## Triage (coordinator, 2026-09-27 10:10Z; owner: "build the clear ones now")

Moving to implementation now: (1) step-17 failure must include the upgrade unit's journal tail so the operator sees the cause, and (2) TLS_CERT_FILE/TLS_KEY_FILE validation must catch host-path-vs-container-path confusion with a clear message. Waiting for owner discussion: the certificate UX flow (belongs to 399), whether the wedged-unit cleanup needs a design decision, and the db-unreachable audit classification.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 The cause of the 24/25 Sep step-17 start timeout is reproduced on v2026.09.2 (LXD replay) and shown fixed or refused with a named cause on v2026.09.3
- [ ] #2 The installer tells a standalone operator to set SITE_DOMAIN (or asks for it) before a certificate can be issued; Ville's hand-edit is not needed
- [ ] #3 A short, confirmed instruction is sent to Ville for the stable v2026.09.3 install with his custom certificate
- [x] #4 The footer never shows 'unknown' when the commit is known: on an install with no release metadata (VERSION empty, COMMIT_SHORT set) it renders something informative such as 'commit bce5bf39' or the commit alone, and the same fallback logic is used everywhere the version is displayed.
- [ ] #5 Where the install path knows the release (install.sh or upgrade from a tagged release), PUBLIC_STATBUS_VERSION is populated so the footer shows the release (for example v2026.10.0); verified on a fresh install, not only in tests.
- [ ] #6 An official installation displays its release: after install.sh from a tagged release or a channel (stable or prerelease), the footer shows that version (for example v2026.10.0) and never the word unknown. A development or local install may show local or dev. The two cases must be distinguishable rather than conflated, and a test must cover the released-install case.
- [ ] #7 DEPLOYMENT.md documents the first steps the field had to discover: downloading install.sh and uninstall.sh from the repository, making them executable with chmod +x, and running them. It must also state the supported channels. (Ville-Mattis Pilvio, 2026-10-08.)
- [ ] #8 User provisioning behaves correctly in every case: explicit STATBUS_USERS_FILE is used and reported; a missing or unreadable explicit path is a hard error; a users file present in the conventional operator location is DETECTED, announced and used rather than ignored; with no file and no path an interactive run asks for the first administrator and reports what was created; an unattended run fails fast with the remedy instead of finishing with no users; and a finished install whose user count is zero, or lower than the supplied file's entries, prints a loud actionable warning.
- [ ] #9 A test covers each provisioning case, including the detected-file case that the field hit, so that a supplied users file can never again be silently unused.
<!-- AC:END -->

## Definition of Done
<!-- DOD:BEGIN -->
- [ ] #1 A test covers the unknown-version/known-commit case and the known-version case; the local install renders an informative footer; the change is small and does not touch the other 422 items (the install-timeout and certificate-path issues stay separate).
<!-- DOD:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
SHORTHAND 404 FIXED AT THE SOURCE, 2026-10-08 (owner-directed). The missing redirect was host-side, not in any repository: /etc/caddy/Caddyfile on niue, in the statbus.org block, handled /install.sh explicitly and sent everything else to https://www.statbus.org{uri}, which does not carry uninstall.sh. Added the mirror block 'handle /uninstall.sh { redir https://raw.githubusercontent.com/statisticsnorway/statbus/refs/heads/master/uninstall.sh 302 }' before the catch-all. Procedure: backup to /etc/caddy/Caddyfile.bak.20261008115655, caddy validate --config /etc/caddy/Caddyfile --adapter caddyfile (OK), systemctl reload caddy (OK). Verified from outside: https://statbus.org/install.sh and https://statbus.org/uninstall.sh both return 200, and the uninstall shorthand delivers the script (first line #!/usr/bin/env bash). The temporary documentation workaround was reverted, so DEPLOYMENT.md advertises the shorthand again now that it works. NOTE for the next person: these shorthand rules live in the host-side Caddyfile, not in the statbus-web checkout, whose deployment SSHes to niue and runs a server-side deploy.sh.
<!-- SECTION:NOTES:END -->
