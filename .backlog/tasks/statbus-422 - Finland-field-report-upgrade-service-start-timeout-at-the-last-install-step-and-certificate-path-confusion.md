---
id: STATBUS-422
title: >-
  Finland field report 2026-09-25: each finding fixed, proven or handed to its
  owner
status: In Progress
assignee: []
created_date: 2026-09-27 10:07
updated_date: '2026-11-07T11:21:00Z'
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
- [ ] #6 [Owner] Ville receives the stable-install instruction with his custom certificate after the owner has tried the certificate picker himself on the plain manual box with the next release (owner decision 2026-10-30); the sent message is recorded in Implementation Notes
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

AC4 partial evidence (an upgraded box, not a fresh install): after rc.03 dev Deploy run 40607897050, a read-only browser visit to https://dev.statbus.org on 2026-10-28 showed the footer exactly 'Statbus version v2026.10.4-rc.03 (18e7d1fe)', not unknown. AC6 remains open.

2026-10-30 (owner): AC6 reworded. Ville waits until the owner has tried the installer's certificate picker on the plain manual box (ops/manual-box.sh cert, walkthrough step 6) with the next release; then the coordinator drafts the message for the owner to send. No dependency on STATBUS-399; STATBUS-429's sudo-free cert install is already in v2026.10.5.

### Picker defects from the manual-box run (v2026.11.0, install.sh + terminal filter), fixed in fceefda17
- **No /etc/ssl search:** certCandidateRoots now searches only the install user's home; the system trust store's ~150 public root CA .pem files are never an installable certificate+key. Notice is now "No certificate files found under ~." "Another file or folder (type a path)" still accepts any path. Red before: TestCertCandidateRootsSearchOnlyHome saw [{home 4} {/etc/ssl 2}]; green after.
- **PFX password layout:** chooseCertificateFromFolder now asks through readPassword with the prompt text; readPassword disables echo first, publishes the prompt on the marked answer line, reads masked stars via the controlling terminal, restores the mode, then writes the line ending to the terminal itself (newline to /dev/tty, since the filter drops unmarked stdout). Red before: TestPFXPasswordPromptFollowsRawModeAndEndsLineOnTerminal and TestCertificateFolderPFXPasswordEndsLineBeforeChoices; green after.
- **Single usable certificate:** shown as one line (path, CN, SANs, expiry, coverage) with "Install this certificate? [Y/n]" (Enter/y installs, n continues without a custom certificate); two or more keep the numbered list and "Install which certificate number". Red before: TestCertificateFolderSingleChoiceAsksConfirmation and ...Declined...; green after; TestCertificateFolderTwoChoicesKeepNumberedList covers the list.
- **Verification:** gofmt clean, go vet ./cmd, go build ./..., targeted tests green (tmp/422-tests-green.log), full ./cmd package green in 68s (tmp/422-cmd-full.log), pre-fix runs red in tmp/422-red-before.log (worktree at 977060062 with the new tests).

### Commits and CI (picker work)
- fceefda17 — picker fixes and tests (Go Test, Harness Selftest initially red on the prompt-derivation grep).
- db04a509a — setup-choices selftest now derives the certificate prompt from askCertYesNo/askCertQuestion; local run PASS ("... [y/N]: ").
- CI on db04a509a: Go Test success, Harness Selftest success, app build & lint success, Images success, CodeQL success, Notify success. The Fast Tests run for that SHA was cancelled by the branch concurrency group when e2da5967d landed; the Go suite and harness that cover this change are green.

### Certificate picker: wrong answer retries, every dead end says what happens next (acf07e3a3)
- askInstallCertPath now asks up to certAttempts (3, matching installinput's askAttempts) and re-asks after a missing path, an unreadable/empty folder, or a PEM certificate without its key. The retry prompt is 'Try another file or folder, or press Enter to continue without a certificate.'; Enter, or the third wrong answer, continues without a certificate.
- Every final dead end prints one sentence through certContinueWithout: 'Continuing with automatic certificates. Install your own later with: ./sb cert install' (decline, empty answer, after retries, declined single certificate, number not in the folder list). No path leaves the choice silently.
- A folder chosen from the ~ list that holds nothing usable now offers the path question instead of ending the choice; a declined single certificate still ends it. certFolderRetry carries that distinction, so the shared chooseCertificateFromFolder signature (and its other tests) is unchanged. PFX password is still asked at most once per folder.
- Tests (red before in tmp/422-retry-red.log, green in tmp/422-retry-green.log): (a) TestInstallCertPathEmptyFolderThenEnterContinues, (b) TestInstallCertPathWrongPathThenValidFolder, (c) TestInstallCertPathThreeWrongAnswersContinues.
- Verification: gofmt clean, go vet ./cmd, go build ./...; go test ./cmd/ -run 'Cert|Picker' -count=1 green (tmp/422-cert-picker-green.log); full go test ./cmd/ green in 68.6s (tmp/422-cmd-full.log); test/install-recovery/tests/setup-choices-driver-test.sh PASS (tmp/422-setup-choices-driver.log).
- One line changed outside the two declared test files: install_cert_folder_choice_test.go asserted the old declined wording 'Continuing without a custom certificate.'; it now asserts the shared sentence, as the ticket's one-sentence rule requires.

### Certificate folder: one leaf, one choice (6d8ea5f5f)
- scanCertificateFolder now merges choices whose leaf certificate is byte-identical (same leaf.Raw). The manual box exports a site certificate as both a PEM pair and a PFX; that folder offered two identical numbered choices.
- The password-free copy (PEM pair) is kept when both are present, else the first; the other file is named on the line as 'also in a-site.pfx' (certChoice.AlsoIn). Different certificates still list separately. PFX choices carry NeedsPassword.
- With one merged choice the existing single-certificate 'Install this certificate? [Y/n]' path applies unchanged.
- Tests (red tmp/422-dedupe-red.log: 2 choices for one leaf; green tmp/422-dedupe-green.log): TestScanCertificateFolderListsOneChoicePerLeaf (PFX sorts first, PEM pair kept, also-in named) and TestScanCertificateFolderKeepsDifferentCertificates.
- Verification after 2122d747b: gofmt clean, go vet ./cmd, go build ./...; go test ./cmd/ -run 'Cert|Picker|Candidate|ScanCertificate' -count=1 green; full go test ./cmd/ green in 84.9s (tmp/422-cmd-full-2.log); setup-choices-driver-test.sh PASS (tmp/422-setup-choices-driver-2.log).
- readPassword and the makeRawTerminal seam were left untouched.

### Certificate picker is ONE pick of certificates, not folders (4258dc6dd)
- Replaced the owner-rejected two-step folder picker. After 'Do you have a certificate to install now? y' the installer lists installable certificates from the same home name search: each PEM certificate file paired with its matching key in the same folder (public-key match; CN, SANs, expiry and site coverage shown), then each PFX/P12 by file name. The best PEM pair is the default; PFX files follow. 'N) Another file or folder (type a path)' remains.
- Exactly one candidate shows its line and asks 'Install this certificate? [Y/n]', with no password and no numbered list. Choosing a PFX asks its password once, shows the certificate it contains, then installs it. A typed path still uses the folder scan, retries and the shared continuing sentence from acf07e3a3.
- Same-certificate deduplication: mergeDuplicateCertificates (6d8ea5f5f) still collapses identical leaves, PEM pair wins. A password-protected PFX cannot be compared without asking, so it stays a separate entry; a password-free PFX collapses into its PEM pair.
- Refactor: pemPairChoices shares the PEM pairing between the folder scan and the picker; scanCertificateFolder behaviour and its tests are unchanged.
- Tests (red tmp/422-onepick-red.log; green tmp/422-onepick-green.log): TestInstallCertPickerOnePickListsCertificates (PEM pair + same password-free PFX -> one candidate, Y/n, no password, no second numbered question), TestInstallCertPickerPEMPairPlusDifferentPFX (two candidates; choosing the PFX with password RightPass returns [pfx], one password read, CN shown, no 'Install which certificate number'), plus updated Another-file-or-folder and invalid-number tests.
- Verification: gofmt clean, go vet ./cmd, go build ./...; go test ./cmd/ -run 'Cert|Picker' -count=1 green; setup-choices-driver-test.sh PASS (tmp/422-setup-choices-driver-3.log). Full go test ./cmd/ has ONE failure unrelated to this work: TestRestartsAfterSettingsRestoreCoverEveryService (install_detection_test.go:655) because 68271b0ad made applyPendingRestarts call composeRestartService, which that test does not fake (tmp/422-cmd-full-3.log). Reported to the coordinator; install.go is not in this worker's files.
- Documentation: no product docs describe the folder list (searched doc/, cli/, ops/); the tracked DEPLOYMENT.md text about the up-front certificate flow remains accurate. tmp/picker-proto/PROPOSAL.md is ignored and still describes the old folder list.

- **2026-11-03, picker noise:** `10404842f`. Giving the home folder listed every ordinary file (.bashrc, the uninstall lock) as 'no PEM certificate or private key found' (manual box, rc.04). Now only files with a certificate extension or a PEM header are reported. `TestScanCertificateFolderReportsOnlyCertificateLookingFiles` red before (`tmp/picker-notes-red.log` in statbus_test), green after; full `go test ./cmd` green. In v2026.11.1-rc.05.

- **2026-11-04, rc.07 box run -> `f9d7f2d8f` (rc.08):** home search found nothing, the operator then ran manual-box cert (PFX into ~/Documents/certificate-from-it) and answered '.' three times; a typed folder was only inspected directly, so the subfolder was never searched. Now a typed folder whose certificates sit in subfolders is searched like the home and offered in the same one pick (pickInstallCert shared with the home search). TestInstallCertPathTypedFolderSearchesBelow reproduces the sequence: red (tmp/cert-typed-folder-red.log: produced []), green (tmp/cert-typed-folder-green.log); all Cert|Picker tests green.

rc.18 manual box 2026-11-07, logs tmp/manual-rc18-setup-evidence.log and tmp/manual-rc18-install-evidence.log (from tmp/statbus-manual-session.log): the owner tried the certificate picker on the plain manual box with rc.18 (the AC6 precondition). Findings fixed and committed for rc.19: three unusable paths now ask 'Do you have a certificate to install now?' again (996b265e1); no to the one found certificate asks for another file or folder (01bd181cf red, f49d10351 green); an expired, not-yet-valid or other-name certificate warns and asks 'Use it anyway?' (0159f7364, aec3bc008 red, b3a8bf399 green); the footer names ./sb cert install when no automatic certificate can come (93399b06d, 5520f129f red, 4d977ceb4 green); cert help names no customer country and says a Windows export is usually a PFX (8a1545301..d090998ba). A PFX copied in mid-run was found, opened with its password, covered the site, and the install completed with HTTPS answering. AC6 remains: send Ville the instruction once the stable release carries these.
<!-- SECTION:NOTES:END -->
