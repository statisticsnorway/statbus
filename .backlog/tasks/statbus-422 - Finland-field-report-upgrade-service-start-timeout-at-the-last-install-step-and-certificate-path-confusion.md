---
id: STATBUS-422
title: >-
  Finland field report 2026-09-25: each finding fixed, proven or handed to its
  owner
status: In Progress
assignee: []
created_date: 2026-09-27 10:07
updated_date: '2026-10-30T13:36:00Z'
labels:
  - installer
dependencies: []
priority: high
type: bug
ordinal: 371200
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
### North Star
Every problem Finland's operator hit on the 2026-09-24/25 install either is fixed and proven, or has a named home, so this field report can close.

### Zoom out
This ticket is a field report, not a feature. A field report is done when each finding is traced to a cause and either fixed here or handed to the ticket that owns it. Mixing several features into one ticket hides which part is still open, so findings that grew into their own work moved out (STATBUS-429, 430, 464, 465, 466, 469). What remains here is only what is not owned elsewhere.

### Zoom in
- **What remains (owner, 2026-10-26):** AC4, the footer showing the release on a fresh install of the next candidate, and AC6, sending Ville the stable-install instruction. Ville is deliberately LAST: he gets the instruction after every other In Progress ticket has been passed, so he receives one working, current answer rather than another intermediate one. In practice that means after STATBUS-429 (sudo-free `./sb cert install`) is proven and stable, and after 399 is no longer in flight. Until then no instruction is sent.
- **Report, Ville-Mattis Pilvio, 2026-09-25 (v2026.09.2):** fresh install on `statbus.statfin.eu`; steps 1-16 green, step 17 `Upgrade service FAILED: enable service: exit status 1` after `Job ... failed because a timeout was exceeded`; his `.env.config` had `TLS_CERT_FILE=/home/statbus/statbus.crt` (a host path) and a hand-added `SITE_DOMAIN`.
- **Step-17 cause, proven:** LXD replay 2026-09-29 (`tmp/ville-replay-v2026.09.3.md`): with a host-path certificate Caddy cannot open the file, the proxy crash-loops, `127.0.0.1:5431` stays unbound, the upgrade service exhausts its 5-minute connect budget and systemd reports exactly that timeout. On v2026.09.3 it is refused with a named cause.
- **Shipped (merge `afd59955a`, v2026.09.3):** service failures include the unit's journal tail (`serviceFailureWithJournal`, `cli/cmd/install.go`); `TLS_CERT_FILE`/`TLS_KEY_FILE` are validated as container paths with a clear message (`cli/internal/config/config.go`).
- **Footer showing `unknown` (found while checking his install log, 2026-10-08):** `ede6945d8` (STATBUS-457) had dropped the configured version from the footer. `3df96b7bf` restores it: ledger identity first, then `PUBLIC_STATBUS_VERSION` when its commit matches the served artifact, else `commit <sha8>`. In v2026.10.1.
- **`SITE_DOMAIN`:** the installer has asked `Domain name` since `b362474b0` (v2026.09.1), so v2026.09.2 already asked; why it was hand-added is not established. The domain advice itself is STATBUS-389.
- **First steps undocumented:** `c5222eb16` (2026-10-08) documents downloading `install.sh`/`uninstall.sh`, `chmod +x`, and the stable and prerelease channels in `doc/DEPLOYMENT.md`.
- **Moved out:** custom-certs writable without sudo (STATBUS-429), transient detection failure shown as a settings error (430), users file silently unused (464, Done), battery heuristic suggesting development (465, Done), development defaults on a country install (466, Done), unreachable Visit URL (469). The private-certificate flow is STATBUS-399.
- **Left as-is:** the audit line `detectedState=db-unreachable` on a healthy database (audit-only wording; STATBUS-402 removed audit vocabulary from operator output).

### Closing review
- **Memory:** none needed.
- **Documentation:** `doc/DEPLOYMENT.md` (done in `c5222eb16`).
- **Cleanup:** the former Definition of Done item (footer test plus local render) duplicated AC3 and was removed.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 The step-17 timeout is traced to its cause (host-path certificate leaves the database route unbound) by an LXD replay, and v2026.09.3 refuses it with a named cause (`tmp/ville-replay-v2026.09.3.md`)
- [x] #2 A failed service start shows the unit's journal tail, and host-path certificate settings are refused with the container-path expectation (`TestServiceFailureWithJournal`, `TestReconcileRestartUsesJournalHelper_STATBUS422`, `TestValidateTLSPaths`)
- [x] #3 The footer shows the release when the configured version's commit matches the served artifact, otherwise `commit <sha8>`, never `unknown` (`running-identity.test.ts`, `footer.test.tsx`, `TestDerivedVersion_ReleaseCheckoutVsDevCheckout`)
- [x] #4 A fresh install of a release containing `3df96b7bf` (v2026.10.1 or later) shows that release in the footer, observed on a real box
- [x] #5 `doc/DEPLOYMENT.md` documents downloading `install.sh` and `uninstall.sh`, `chmod +x`, and the supported channels (`c5222eb16`)
- [ ] #6 Ville receives the stable-install instruction with his custom certificate after the owner has tried the certificate picker himself on the plain manual box with the next release (owner decision 2026-10-30); the sent message is recorded in Implementation Notes
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
### Evidence
- **AC1:** LXD replay 2026-09-29, recorded in `22c8fddcf`.
- **AC2-3:** green locally on master, 2026-10-15 (Go tests and 27 app tests).
- **AC4:** open; v2026.10.1 contains `3df96b7bf` but no fresh-install footer observation is recorded.
- **AC5:** `doc/DEPLOYMENT.md` lines 194-240.
- **AC6:** open.
- **Consolidated:** former AC5 and AC6 (both "the footer shows the release on a fresh install") are now AC4. Former AC8 and AC9 (users file) were done by STATBUS-464 and removed here. Former AC2 (`SITE_DOMAIN`) was already asked in v2026.09.2; the domain advice is STATBUS-389.
- **Installer-log review cluster (2026-10-08):** three defects from Ville's install log became STATBUS-464, 465 and 466; all three are Done.

### AC4 state (2026-10-16)
- Footer read from outside: dev, demo and no show v2026.10.2-rc.01; et v2026.09.0, jo v2026.08.0, ma v2026.09.3, ug v2026.09.0. No box shows `unknown`. All of these were upgraded, not freshly installed.
- The fresh install comes from the owner's Uganda install at v2026.10.2 (STATBUS-497). Its footer read is requested there; AC4 closes on that observation.

### Owner decision 2026-10-26: Ville waits for the sweep
Do not send Ville the stable-install instruction yet. He is contacted after every other In Progress ticket has been passed. No dependency on STATBUS-399 for him (it is the no-public-DNS case); the practical dependency is 429's proven sudo-free `./sb cert install` plus a stable release. AC6 stays open until then.

AC4 real-box evidence: after rc.03 dev Deploy run 40607897050, a read-only browser visit to https://dev.statbus.org on 2026-10-28 showed the footer exactly 'Statbus version v2026.10.4-rc.03 (18e7d1fe)', not unknown. AC6 remains open.

2026-10-30 (owner): AC6 reworded. Ville waits until the owner has tried the installer's certificate picker on the plain manual box (ops/manual-box.sh cert, walkthrough step 6) with the next release; then the coordinator drafts the message for the owner to send. No dependency on STATBUS-399; STATBUS-429's sudo-free cert install is already in v2026.10.5.
<!-- SECTION:NOTES:END -->
