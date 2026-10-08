---
id: STATBUS-422
title: >-
  Finland field report: upgrade-service start timeout at the last install step,
  and certificate path confusion
status: In Progress
assignee: []
created_date: '2026-09-27 10:07'
updated_date: '2026-10-08 10:44'
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
<!-- AC:END -->

## Definition of Done
<!-- DOD:BEGIN -->
- [ ] #1 A test covers the unknown-version/known-commit case and the known-version case; the local install renders an informative footer; the change is small and does not touch the other 422 items (the install-timeout and certificate-path issues stay separate).
<!-- DOD:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
VERSION PLUMBING EVIDENCE (coordinator, 2026-10-08), for whoever fixes the version display. cli/internal/config/config.go writes VERSION=%[22]s, COMMIT_SHORT=%[23]s, PUBLIC_STATBUS_VERSION=%[22]s and PUBLIC_STATBUS_COMMIT_SHORT=%[23]s into the generated .env, so the displayed version is the config Version value. install.sh DOES know the release: it accepts --version, honours STATBUS_INSTALL_VERSION, and resolves the tag from the GitHub releases API for channel stable or prerelease (around lines 670-690), with a development fallback to git rev-parse --short=8 HEAD (line 727). So the installer is not unable to know the version; the defect is in how that known release version reaches ./sb config generate and config.Version. That is the owner's point: the development path and the released-install path are being conflated, which is why an official installation showed 'unknown (bce5bf39)'.
UNINSTALLER POINT (owner asked to capture it, 2026-10-08): NO COMPLAINT FOUND IN THE REPORT AS RECEIVED. Ville's message says the opposite, 'short answer: uninstall and install (deployment) run without issues', and his only ask was to document the download and chmod step, which is now an acceptance criterion here. The earlier 2026-09-25 report does mention a leftover failed systemd unit that needed manual removal before step 17 passed, so the recollection may come from there or from a later message not yet forwarded. Action: do NOT invent a symptom. The uninstall path is already covered by test/install-recovery/scenarios/6-uninstall-reinstall.sh, so the honest next step is to run that scenario or review uninstall.sh against the state install.sh creates, and to add the exact error text here if the owner has it.

FOOTER VERSION FIX 2026-10-08, commit 3df96b7b. PLUMBING BREAK FOUND: the release was never lost on the install path. install.sh detaches at refs/tags/<tag>; ./sb config generate derives VERSION from git describe --tags --always, giving exactly v2026.10.0 on that shallow tag checkout (reproduced locally and pinned by cli/internal/config/version_test.go); .env carries VERSION and PUBLIC_STATBUS_VERSION; compose passes PUBLIC_STATBUS_VERSION; layout.tsx injects it as fallbackVersion. The break was in the app: ede6945d8 (STATBUS-457 artifact binding, 2026-10-06, an ancestor of bce5bf39) dropped fallbackVersion from runningVersionDisplay, so whenever public.release_identity(artifact SHA) returned no row the footer printed the literal 'unknown'. FIX: runningVersionDisplay resolves the ledger identity first. Failing that, it uses the configured PUBLIC_STATBUS_VERSION, but only when PUBLIC_STATBUS_COMMIT_SHORT is a prefix of the served artifact SHA, so a rolled-back .env never labels another artifact. Failing that, it shows 'commit <sha8>'. The values local, unknown and a bare hash carry no name. The footer and the admin Running card share this logic. RESULT: a released install shows 'v2026.10.0 (bce5bf39)'. A dev checkout shows its describe (e.g. v2026.10.0-48-gd7ae1f231) linked to the commit, which is distinct from a release. With no version, the footer shows 'commit <sha8>'. Tests: app running-identity.test.ts, footer.test.tsx, Go version_test.go. AC #5 still needs a fresh-install observation of a release that contains 3df96b7b.
<!-- SECTION:NOTES:END -->
