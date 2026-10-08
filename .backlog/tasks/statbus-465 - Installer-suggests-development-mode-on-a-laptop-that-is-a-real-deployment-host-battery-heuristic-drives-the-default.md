---
id: STATBUS-465
title: >-
  Installer suggests development mode on a laptop that is a real deployment host
  (battery heuristic drives the default)
status: To Do
assignee: []
created_date: '2026-10-08 12:01'
updated_date: '2026-10-08 12:04'
labels:
  - installer
dependencies: []
priority: high
ordinal: 391204
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
DECISION (owner, 2026-10-08, FINAL): THE INSTALLER ALWAYS SUGGESTS STANDALONE. No heuristics and no detection of any kind. Running the installer IS a standalone installation. Anything else, development or private, is something the operator does on purpose, so the operator chooses it explicitly. The modes keep their explanations, so nobody is misled about what they are picking.

WHY DETECTION IS NOT THE ANSWER (owner's question, verified 2026-10-08). The installer is itself invoked inside a git checkout: install.sh line 14 records that a fresh install has no ~/statbus/.git and therefore clones the repository, and line 21 states that the directory is ALWAYS created by git clone, never mkdir. ./sb install then runs inside that clone. A normal standalone installation therefore IS a checkout, so 'is this a git checkout' cannot distinguish a developer from an operator. Detect nothing.

CURRENT ALGORITHM, FOR THE RECORD. 1) cli/cmd/install_host.go: installIsLaptopAt reads /sys/class/power_supply and returns true when an entry whose name begins with BAT (case-insensitive) has a type file containing Battery. 2) cli/cmd/install.go around line 1750: modeDefault := standalone, then set to development when installIsLaptop() returns true. 3) cli/internal/installinput/config.go around lines 88-92: AskWithMode replaces the CADDY_DEPLOYMENT_MODE question's own fallback with that value, which is why the field table's static default (development) does not appear in interactive runs. The Finland log showing [development] proves the battery check returned true on that host, whose name PB14250 is Lenovo-style, and the operator then accepted it, which is how a country deployment ended up as a self-hosting-only box.

REQUIRED BEHAVIOUR.
1. The suggested deployment mode is constant: standalone. Nothing about hardware, checkout state, hostname, or any other input changes it.
2. installIsLaptop, installIsLaptopAt and their tests are removed, since nothing consults them any more.
3. The CADDY_DEPLOYMENT_MODE fallback in the field table is standalone, so no code path, interactive or not, can suggest development by accident.
4. development and private remain selectable, the prompt keeps explaining what each mode means, and private is never suggested automatically.
5. Tests assert the suggestion is standalone with a battery directory present and absent, and do not depend on the hardware of the machine running the suite.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 The suggested deployment mode is always standalone; no hardware signal, checkout state, hostname or other input changes it.
- [ ] #2 installIsLaptop, installIsLaptopAt and their tests are removed, since nothing consults them any more.
- [ ] #3 The CADDY_DEPLOYMENT_MODE fallback in the field table is standalone, so no code path can suggest development by accident.
- [ ] #4 development and private remain selectable, the prompt keeps explaining each mode, and private is never suggested automatically.
- [ ] #5 Tests assert the suggestion is standalone with a battery directory present and absent, without depending on the hardware of the machine running the suite.
<!-- AC:END -->

## Definition of Done
<!-- DOD:BEGIN -->
- [ ] #1 Verified through the interactive install path with the observed prompt recorded, not only by a unit test.
- [ ] #2 Verified through the interactive install path with the observed prompt recorded, not only by a unit test.
- [ ] #3 Verified through the interactive install path with the observed prompt for each context recorded, not only by a unit test.
- [ ] #4 Verified through the interactive install path with the observed prompt recorded, not only by a unit test.
<!-- DOD:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Origin: the owner reviewing the Finland installer log on 2026-10-08 asked whether our default is development; the answer is that the code intends standalone and the battery heuristic made his laptop host default to development. Related field context: STATBUS-422.
<!-- SECTION:NOTES:END -->
