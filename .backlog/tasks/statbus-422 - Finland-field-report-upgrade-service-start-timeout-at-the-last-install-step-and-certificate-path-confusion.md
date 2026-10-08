---
id: STATBUS-422
title: >-
  Finland field report: upgrade-service start timeout at the last install step,
  and certificate path confusion
status: In Progress
assignee: []
created_date: '2026-09-27 10:07'
updated_date: '2026-10-08 11:49'
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
PRINCIPLED USER PROVISIONING (owner directive 2026-10-08: handle each case, do not document ourselves into a corner). The installer must never silently ignore an operator-supplied users file and must never ask for a user it already has. Every path below states what is used, what is created, and how many users resulted.

INPUTS: an explicit file path via STATBUS_USERS_FILE; an interactive first-administrator answer (email, name, password entered without echo); a file present in the conventional operator location; or nothing.

CASES AND REQUIRED BEHAVIOUR.
1. STATBUS_USERS_FILE set and readable: use it, skip the interactive user question entirely, copy it into the project as .users.yml, and print the path plus the number of users created. Unattended runs never prompt when this is set.
2. STATBUS_USERS_FILE set but missing or unreadable: hard error naming the path (this is already the behaviour, 'read STATBUS_USERS_FILE %q'). Never fall back to a prompt silently.
3. No explicit path, but a users file EXISTS in the conventional operator location: DETECT it and SAY SO, then use it, for example 'Found ~/statbus.users.yml with 3 users; using it.' In an interactive run it may ask once to confirm; in an unattended run it uses it and says so. It must not be ignored, which is the failure the field hit today. This is the case that previously ended with the operator's file quietly unused and a box that could not be logged into.
4. No explicit path and no file, interactive: ask for the first administrator as today, then state what was created, for example 'Created administrator admin@example.com.'
5. No explicit path and no file, unattended: fail fast with the exact remedy (set STATBUS_USERS_FILE, or place a users file in the conventional location), instead of completing an install with no users.
6. After either path: if the resulting user count is zero, or lower than the number of entries in the file that was supplied, print a loud actionable warning with the command to fix it (./sb users create after placing the file at ~/statbus/.users.yml). An install that ends unable to log in must say so at the end, not leave the operator to discover it.
7. Conflicts are resolved explicitly, in the same spirit as the existing --version versus STATBUS_INSTALL_VERSION conflict: an explicit path wins over a detected file and over the prompt, and a detected file wins over the prompt. A contradiction between two explicit inputs is an error, not a silent preference.

FOR THE INSTALLER IMPLEMENTATION: the current code deliberately does not discover a file ('explicit and optional, never discovered by a hidden home-directory name', cli/cmd/install.go around lines 1773-1783). Case 3 changes that decision deliberately, using the operator location documented in STATBUS-437 rather than a hidden name. That ticket's convention (flat files in the operator's home) is the sane place to land it.
<!-- SECTION:NOTES:END -->
