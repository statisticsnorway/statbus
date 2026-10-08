---
id: STATBUS-465
title: >-
  Installer suggests development mode on a laptop that is a real deployment host
  (battery heuristic drives the default)
status: To Do
assignee: []
created_date: '2026-10-08 12:01'
updated_date: '2026-10-08 12:02'
labels:
  - installer
dependencies: []
priority: high
ordinal: 391204
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
DECISION (owner, 2026-10-08): REMOVE THE HARDWARE HEURISTIC AND LET THE SUGGESTED MODE FOLLOW HOW THE INSTALL IS INVOKED. The modes describe audiences, not hardware:
* Someone running the OFFICIAL INSTALLER from the internet is doing a STANDALONE installation, so standalone is what we suggest to them.
* Someone with code access runs from a GIT CHECKOUT, and development is a sensible suggestion for them.
* PRIVATE CLOUD is OUR installation shape (SSB runs the multi-tenant cloud), so it is never suggested; it is chosen deliberately.
A battery, or any other hardware signal, must never influence the suggestion.

CURRENT ALGORITHM, FOR THE RECORD. 1) cli/cmd/install_host.go: installIsLaptopAt reads /sys/class/power_supply and returns true when an entry whose name begins with BAT (case-insensitive) has a type file containing Battery. 2) cli/cmd/install.go around line 1750: modeDefault := standalone, then set to development when installIsLaptop() returns true. 3) cli/internal/installinput/config.go around lines 88-92: AskWithMode replaces the CADDY_DEPLOYMENT_MODE question's own fallback with that value, which is why the field table's static default (development) does not appear in interactive runs. The Finland log showing [development] proves the battery check returned true on that host, whose name PB14250 is Lenovo-style.

REQUIRED BEHAVIOUR.
1. The battery check is removed: installIsLaptop, installIsLaptopAt and their tests go with it, and nothing about the suggested mode depends on the machine's hardware.
2. The suggested mode is derived from the invocation context. Running from a git checkout (code access) may suggest development. Running the installer that did not come from a checkout, such as the downloaded or piped official installer, suggests standalone. The signal used must be explicit in the code and covered by tests.
3. private is never the suggested value. It stays an explicit choice, and the prompt keeps explaining what each mode means.
4. The CADDY_DEPLOYMENT_MODE fallback in the field table is standalone, so no code path can suggest development by accident.
5. Tests cover both invocation contexts and assert hardware independence, meaning the presence or absence of a battery directory changes nothing, and they must not depend on the hardware of the machine running the suite.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 The battery check and its helpers are removed, and no hardware signal influences the suggested deployment mode.
- [ ] #2 The suggested mode follows the invocation context: a git checkout suggests development, while the official installer path that did not come from a checkout suggests standalone; the signal used is explicit in the code.
- [ ] #3 private is never suggested automatically; it remains an explicit choice, and the prompt keeps explaining what each mode means.
- [ ] #4 The CADDY_DEPLOYMENT_MODE fallback in the field table is standalone, so no code path can suggest development by accident.
- [ ] #5 Tests cover both invocation contexts and assert hardware independence, without depending on the hardware of the suite host.
<!-- AC:END -->

## Definition of Done
<!-- DOD:BEGIN -->
- [ ] #1 Verified through the interactive install path with the observed prompt recorded, not only by a unit test.
- [ ] #2 Verified through the interactive install path with the observed prompt recorded, not only by a unit test.
- [ ] #3 Verified through the interactive install path with the observed prompt for each context recorded, not only by a unit test.
<!-- DOD:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Origin: the owner reviewing the Finland installer log on 2026-10-08 asked whether our default is development; the answer is that the code intends standalone and the battery heuristic made his laptop host default to development. Related field context: STATBUS-422.
<!-- SECTION:NOTES:END -->
