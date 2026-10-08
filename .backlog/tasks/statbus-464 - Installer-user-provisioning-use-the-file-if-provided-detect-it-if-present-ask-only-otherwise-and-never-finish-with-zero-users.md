---
id: STATBUS-464
title: >-
  Installer user provisioning: use the file if provided, detect it if present,
  ask only otherwise, and never finish with zero users
status: In Progress
assignee: []
created_date: '2026-10-08 11:57'
updated_date: '2026-10-08 12:12'
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
- [ ] #1 STATBUS_USERS_FILE set and readable: it is used, the interactive user question is skipped entirely, the file is copied into the project as .users.yml, and the output states the path and the number of users created; unattended runs never prompt in this case.
- [ ] #2 STATBUS_USERS_FILE set but missing or unreadable: hard error naming the path, with no silent fallback to the prompt.
- [ ] #3 No explicit path but a users file exists in the conventional operator location: it is DETECTED and ANNOUNCED ('Found <path> with N users; using it'), then used. Interactive runs may confirm once; unattended runs use it and say so. It is never silently ignored, which is the field failure this ticket exists to prevent.
- [ ] #4 No explicit path and no file, interactive: the installer asks for the first administrator (email, name, password entered without echo) and then states what was created.
- [ ] #5 No explicit path and no file, unattended: the installer fails fast with the exact remedy (set STATBUS_USERS_FILE or place a users file in the conventional location) instead of completing an install with no users.
- [ ] #6 After provisioning, if the resulting user count is zero, or lower than the number of entries in the supplied file, a loud actionable warning names the command that fixes it (./sb users create after placing the file at the conventional path).
- [ ] #7 Conflicts resolve explicitly and are tested: an explicit path beats a detected file, a detected file beats the prompt, and a contradiction between two explicit inputs is an error rather than a silent preference.
- [ ] #8 Each provisioning case above has a test that fails without the behaviour, including the detected-file case and the zero-user end state, and the tests are run by the implementer with the output recorded in the ticket.
- [ ] #9 After the first administrator is created interactively, with no users file supplied anywhere, the installer persists that entry to the operator-home users file at the documented STATBUS-437 location with mode 0600 and states in its output that it did so, without printing the password. A subsequent install on the same box reuses it and does not ask for the first administrator again.
<!-- AC:END -->

## Definition of Done
<!-- DOD:BEGIN -->
- [ ] #1 The detection rule uses the operator-home convention documented in STATBUS-437 (a documented location, not a hidden filename), and the decision that the current 'never discovered' behaviour is being reversed is stated in the code comment it replaces.
- [ ] #2 Verified on a real install path, not only unit tests: at minimum the interactive-admin scenario in test/install-recovery and the unattended path, with the observed output recorded.
<!-- DOD:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
ADDED CASE (owner question 2026-10-08: 'Will it also populate the .users.yml for the next time?'). TODAY THE ANSWER IS NO. runCreateUsers in cli/cmd/install.go lines 3131-3159: if <dir>/.users.yml exists it calls applyUsersYML and returns; otherwise it prompts for Email, Name and Password and then runs 'SELECT public.user_create(p_display_name => ..., p_email => ..., p_statbus_role => "admin_user", p_password => ...)'. It creates the database user and never writes a users file. Consequence: the credentials the operator typed exist only in the database, so a later install on the same box asks for the first administrator again, and the identity does not survive a fresh checkout. The installer only ever writes .users.yml when an explicit STATBUS_USERS_FILE was supplied, in which case it copies that file into the project (install.go line 1781). REQUIRED BEHAVIOUR TO ADD: after an interactive first-administrator creation, persist the entry to the operator-home users file at the documented STATBUS-437 location with mode 0600, and say so in the output without printing the password, so the next install reuses it and STATBUS-437's survive-the-checkout property holds. Note the trust level is unchanged: the users file format already holds plaintext passwords at 0600, and the documented warning is about not putting passwords in guides or shell commands, not about the sanctioned answers file. This also feeds the detection case above: the file this writes is the file that case then finds.
<!-- SECTION:NOTES:END -->
