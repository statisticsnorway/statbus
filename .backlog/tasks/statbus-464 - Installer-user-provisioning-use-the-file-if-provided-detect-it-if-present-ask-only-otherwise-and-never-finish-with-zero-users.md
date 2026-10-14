---
id: STATBUS-464
title: >-
  Installer user provisioning: use the file if provided, detect it if present,
  ask only otherwise, and never finish with zero users
status: Done
assignee: []
created_date: '2026-10-08 11:57'
updated_date: '2026-10-08 15:05'
labels:
  - installer
  - docs
dependencies: []
priority: high
ordinal: 390204
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
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
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 STATBUS_USERS_FILE set and readable: it is used, the interactive user question is skipped entirely, the file is copied into the project as .users.yml, and the output states the path and the number of users created; unattended runs never prompt in this case.
- [x] #2 STATBUS_USERS_FILE set but missing or unreadable: hard error naming the path, with no silent fallback to the prompt.
- [x] #3 No explicit path but a users file exists in the conventional operator location: it is DETECTED and ANNOUNCED ('Found <path> with N users; using it'), then used. Interactive runs may confirm once; unattended runs use it and say so. It is never silently ignored, which is the field failure this ticket exists to prevent.
- [x] #4 No explicit path and no file, interactive: the installer asks for the first administrator (email, name, password entered without echo) and then states what was created.
- [x] #5 No explicit path and no file, unattended: the installer fails fast with the exact remedy (set STATBUS_USERS_FILE or place a users file in the conventional location) instead of completing an install with no users.
- [x] #6 After provisioning, if the resulting user count is zero, or lower than the number of entries in the supplied file, a loud actionable warning names the command that fixes it (./sb users create after placing the file at the conventional path).
- [x] #7 Conflicts resolve explicitly and are tested: an explicit path beats a detected file, a detected file beats the prompt, and a contradiction between two explicit inputs is an error rather than a silent preference.
- [x] #8 Each provisioning case above has a test that fails without the behaviour, including the detected-file case and the zero-user end state, and the tests are run by the implementer with the output recorded in the ticket.
- [x] #9 After the first administrator is created interactively, with no users file supplied anywhere, the installer persists that entry to the operator-home users file at the documented STATBUS-437 location with mode 0600 and states in its output that it did so, without printing the password. A subsequent install on the same box reuses it and does not ask for the first administrator again.
<!-- AC:END -->

## Definition of Done
<!-- DOD:BEGIN -->
- [x] #1 The detection rule uses the operator-home convention documented in STATBUS-437 (a documented location, not a hidden filename), and the decision that the current 'never discovered' behaviour is being reversed is stated in the code comment it replaces.
- [x] #2 The provisioning tests are shown CONSEQUENTIAL, not merely green: at 442b0b38b^ (before the fix) the current tests are run and each failing case is recorded - explicit STATBUS_USERS_FILE used and reported, a broken users file a hard error, an unattended run with no users refusing up front and naming the remedy, contradicting files refusing - and the same tests are then recorded passing at HEAD.
- [x] #3 The two install-path claims that are genuinely about the host are recorded as ONE observation each from the real install path (the interactive first-administrator prompt, and the unattended refusal), not built out into a scenario catalogue.
<!-- DOD:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
COORDINATOR VERIFICATION 2026-10-08 of 442b0b38b, with its evidence commit 9f1be5b09. The landed change is substantial and tested: cli/cmd/install_users.go (359 new lines) with install_users_test.go (458 lines), plus changes in install.go, users.go, doc/DEPLOYMENT.md, install.sh and ops/install-terminal-output.awk. Verified from the worker's logs and independently: golangci-lint 0 issues across 28 packages; go test ./cmd ok (75.4 s) and ./cmd/release ok (105.7 s); and the case tests pass, including TestUsersCase7ConflictsResolveExplicitly, TestUsersLinesPassTheTerminalFilter and TestUsersEstablishedBoxStepSemantics. CI for that SHA: classify, seed and the three manifest jobs are green, the pg_regress fast suite is in progress, and one earlier run was cancelled as superseded, which is that workflow's normal behaviour. REMAINING, as the worker states: a real install-path verification, the interactive-admin scenario plus the unattended path, rather than unit tests alone. The ticket therefore stays In Progress until that run happens, and it needs a machine or a ready local database.

REAL-INSTALL AND RED/GREEN EVIDENCE, 2026-10-08 (worker, candidate 6c4786a18, which contains 442b0b38b).

A. RED/GREEN: is each test consequential? The CURRENT cli/cmd/install_users_test.go (unchanged from 442b0b38b) was run at the fix parent 442b0b38b^ = 889bcf6f9 in a scratch worktree. The parent has none of the test's symbols, so a compile-only shim was added there (kept in tmp/464-evidence/evidence_shim_464.go plus 464-parent-shim.diff). The shim routes the parent's own runCreateUsers and checkUsersDone through the test's seams, extracts the parent's users-file preflight verbatim as validateUsersInput, models only the parent's one file input (explicit STATBUS_USERS_FILE copied into .users.yml), and makes reportInstallUsers a no-op because the parent had no end-of-install report. It adds none of the fix's behaviour. Result at the parent (go test ./cmd -run TestUsers -v, tmp/464-evidence/464-red-parent.log):
- AC#1 TestUsersCase1ExplicitFileIsUsedAndReported: FAIL. A probe that first applies the parent's own Configuration-step copy shows the true pre-fix behaviour: 'runCreateUsers err=<nil>, created=2, stdout=""'. The file WAS used, but silently: no path, no count.
- AC#2 TestUsersCase2ExplicitFileProblemsAreHardErrors: FAIL on all 3 subtests. 'empty' and 'incomplete' got <nil> at preflight, so the parent accepted a file that creates nobody. 'missing' was already a hard error at the parent ('read STATBUS_USERS_FILE "...absent.yml": open ...: no such file or directory'), as the ticket says. Its red is only the message shape, not the behaviour.
- AC#3 TestUsersCase3DetectedHomeFileIsAnnouncedAndUsed: FAIL, because ~/statbus.users.yml was ignored and the unattended step refused ('The first administrator must be created in a terminal...'). That is the field failure. TestUsersCase3DetectedProjectFileIsAnnounced: FAIL ('project file not announced').
- AC#4/AC#9 TestUsersCase4InteractiveAdminIsCreatedSavedAndReused: FAIL. Missing 'Created administrator first-admin@example.org.' and 'Saved the administrator to .../statbus.users.yml (mode 0600)...', and the home file does not exist.
- AC#5 TestUsersCase5UnattendedWithoutUsersFailsFast: FAIL ('preflight: got <nil>'). The parent passed preflight with no users at all.
- AC#6 TestUsersCase6EndStateWarnings: FAIL ('zero-user end state not warned'). TestUsersLinesPassTheTerminalFilter: FAIL, because the awk filter dropped the lines.
- AC#7 TestUsersCase7ConflictsResolveExplicitly: 4 of 5 subtests FAIL (explicit beats home: precedence not stated; detected beats prompt: it prompted; explicit vs project file: got <nil>; home vs project disagree: got <nil>). The 5th, 'identical files by meaning are not a contradiction', PASSES at the parent by design: it guards against over-refusal, and the parent refused nothing.
- TestUsersEstablishedBoxStepSemantics: FAIL ('explicit file with absent users was considered done').
GREEN at 6c4786a18, the same command: all 11 tests and every subtest PASS (tmp/464-evidence/464-green-head.log).

B. REAL INSTALL PATH, recorded for the record and not to be expanded further. A hardened Hetzner harness VM (Ubuntu 26.04, statbus-recovery-464-users-evidence-48825, now DELETED) ran the real in-repo install.sh --commit 6c4786a186d6a29fe8895211f50a1ed59250a109, which procures the published statbus-sb:6c4786a1. Each command runs as user statbus; full logs are in tmp/464-evidence/{refusals,interactive,rerun,established,zero,fresh}.log.
Refusals, all unattended with --non-interactive and STATBUS_ENV_CONFIG; each exited 78, started no containers and wrote no .env.config:
- R1, no users file anywhere: 'No users file was found and this run cannot ask for the first administrator. Set STATBUS_USERS_FILE to your users file, or place it at /home/statbus/statbus.users.yml, then run the same install command again: curl -fsSL https://statbus.org/install.sh | env STATBUS_ENV_CONFIG=/home/statbus/install-input.env bash -s -- --commit 6c47... --non-interactive'
- R2, STATBUS_USERS_FILE missing: 'STATBUS_USERS_FILE /home/statbus/no-such-users.yml cannot be read. Check the path and its permissions, then run the same install command again: ...'
- R3a, ~/statbus.users.yml lists nobody: 'the users file /home/statbus/statbus.users.yml cannot be used: it lists no users. Correct it, then run ...'
- R3b and R3c, an entry without a password (detected and explicit): '... cannot be used: an entry is missing email, display_name or password. Correct it, then run ...'
- R4a, home and project files differ: 'the users files /home/statbus/statbus.users.yml and /home/statbus/statbus/.users.yml list different users. Keep one, or make them identical, then run ...'
- R4b, explicit and project files differ: 'the users files /home/statbus/explicit-users.yml and /home/statbus/statbus/.users.yml list different users. ...'
Interactive, on a real PTY via expect, with no STATBUS_ENV_CONFIG and no users file anywhere:
- '[17/18] Administrator RUNNING / Create the first administrator. Everyone else is invited from the web interface. / Email []: first-admin@statbus.org / Name []: First Admin / Password (typing is hidden): Password again: Created administrator first-admin@statbus.org. / Saved the administrator to /home/statbus/statbus.users.yml (mode 0600) so a later install reuses it. ... User accounts: 1 / Installation complete!', exit 0.
- Checked afterwards: ~/statbus.users.yml is '-rw------- 600 statbus:statbus' and byte-identical to ~/statbus/.users.yml. auth.user holds first-admin@statbus.org with admin_user. PostgREST /rpc/login answers HTTP 200 with is_authenticated=true. The password appears in no capture or log file (install transcript, install-last-run-output.txt, install-logs, upgrade-logs).
- Rerun on the same PTY: every step OK, 'User accounts: 1 / All steps complete. Nothing to do.', with no Email prompt.
Established box:
- E1, a second user appended to the files: 'User accounts: 1 / ⚠ USERS: /home/statbus/statbus.users.yml lists 2 users but 1 of them do not exist. Place the users file at /home/statbus/statbus/.users.yml, then run: cd /home/statbus/statbus && ./sb users create'. No account was resurrected.
- E2, the same file given as STATBUS_USERS_FILE: 'Using STATBUS_USERS_FILE /home/statbus/statbus.users.yml with 2 users. / Created 1 users from ...; 1 already existed and were left unchanged. / User accounts: 2'.
- E3, all accounts deleted and no file: the Administrator step FAILED with exit 78 and the same R1 remedy. The plain './sb install --non-interactive' gave the same refusal with the rerun 'cd /home/statbus/statbus && ./sb install'.
- E4, file restored: 'Found /home/statbus/statbus.users.yml with 2 users; using it. / Created 2 users ... / User accounts: 2'.
Fresh installs after a full './sb uninstall', which removed the checkout, containers and volumes and left ~/statbus.users.yml intact:
- F2, unattended, home file only: 'Found /home/statbus/statbus.users.yml with 2 users; using it. / Created 2 users ... / User accounts: 2'. The project .users.yml is 600 and identical to the home file.
- F3, explicit file differing from the home file: 'Using STATBUS_USERS_FILE /home/statbus/explicit-users.yml with 1 users. / Not using /home/statbus/statbus.users.yml: STATBUS_USERS_FILE was given explicitly and takes precedence. / Created 1 users ... / User accounts: 1'. The project .users.yml is identical to the explicit file.
- F4, pre-placed ~/statbus/.users.yml only: 'Found /home/statbus/statbus/.users.yml with 1 users; using it. ... User accounts: 1'.
Observation: no real run printed the zero-account line '⚠ USERS: no user account exists'. Every zero-user path refused BEFORE completion (R1, E3) instead of finishing, which is the stronger outcome. That warning line is proven by TestUsersCase6 (red at the parent, green at HEAD), not by a live run.

DoD#1: the comment at cli/cmd/install.go:1817 states 'STATBUS-464 REVERSES the earlier rule ... never discovered by a hidden home-directory name' and names ~/statbus.users.yml as STATBUS-437's documented convention (437's ticket lists ~/statbus.users.yml among its flat visible input files; doc/DEPLOYMENT.md:394 documents it). DoD#2: the interactive-admin flow and the unattended path were run through the real install.sh on a real hardened VM, as observed above. The scenario FILE test/install-recovery/scenarios/0-interactive-admin-password.sh was not invoked, because it requires a release tag at HEAD and none exists. The same flow was driven by hand on a VM provisioned by the same bootstrap_install_test_vm.

DoD MAPPING (the DoD was renumbered while this evidence was being gathered). DoD#2, the red/green consequence: section A above; all 11 tests are red at 889bcf6f9 except Case7's over-refusal guard, which passes by design, and all are green at 6c4786a18. DoD#3, one real install-path observation per host claim: (a) the interactive first-administrator prompt is the PTY install.sh run in section B. It asked Email, Name and the hidden password twice, printed 'Created administrator first-admin@statbus.org.' and 'Saved the administrator to /home/statbus/statbus.users.yml (mode 0600)...', login returned 200 with is_authenticated=true, and the password was absent from every log. (b) The unattended refusal is section B's R1: exit 78 with 'No users file was found and this run cannot ask for the first administrator. Set STATBUS_USERS_FILE ... or place it at /home/statbus/statbus.users.yml, then run the same install command again: <exact rerun>'. The extra B cases (R2-R4, E1-E4, F2-F4) were run before the coordinator's stop instruction. They are recorded, not expanded.
<!-- SECTION:NOTES:END -->
