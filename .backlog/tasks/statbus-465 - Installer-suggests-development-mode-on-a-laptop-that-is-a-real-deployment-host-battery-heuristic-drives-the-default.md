---
id: STATBUS-465
title: >-
  Installer suggests development mode on a laptop that is a real deployment host
  (battery heuristic drives the default)
status: In Progress
assignee: []
created_date: '2026-10-08 12:01'
updated_date: '2026-10-08 14:46'
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
- [x] #1 The suggested deployment mode is always standalone; no hardware signal, checkout state, hostname or other input changes it.
- [x] #2 installIsLaptop, installIsLaptopAt and their tests are removed, since nothing consults them any more.
- [x] #3 The CADDY_DEPLOYMENT_MODE fallback in the field table is standalone, so no code path can suggest development by accident.
- [x] #4 development and private remain selectable, the prompt keeps explaining each mode, and private is never suggested automatically.
- [x] #5 Tests assert the suggestion is standalone with a battery directory present and absent, without depending on the hardware of the machine running the suite.
<!-- AC:END -->

## Definition of Done
<!-- DOD:BEGIN -->
- [x] #1 TestSuggestedModeIsStandaloneWithOrWithoutBattery is shown CONSEQUENTIAL: at 054611d1d^ (where the battery heuristic exists) it FAILS with a battery directory present, and at HEAD it passes, with both outputs recorded in the ticket.
- [ ] #2 The one host-level claim is recorded from a single real interactive observation: on a host that presents a battery, the CADDY_DEPLOYMENT_MODE prompt suggests standalone, and development and private remain selectable with their explanations. One observation, not a scenario catalogue.
<!-- DOD:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Origin: the owner reviewing the Finland installer log on 2026-10-08 asked whether our default is development; the answer is that the code intends standalone and the battery heuristic made his laptop host default to development. Related field context: STATBUS-422.

COORDINATOR VERIFICATION of the landed code (054611d1d, verified against the tree at 6c4786a18 on 2026-10-08). AC1/AC3: cli/internal/installinput/config.go now has 'const SuggestedMode = "standalone"' and the field table's CADDY_DEPLOYMENT_MODE row uses SuggestedMode, so no code path can suggest development by accident. AC2: rg finds no installIsLaptop, installIsLaptopAt or install_host references anywhere in cli/; the commit removed cli/cmd/install_host.go and cli/cmd/install_guidance_test.go. AC4/AC5: cli/cmd/install_mode_suggestion_test.go holds TestSuggestedModeIsStandaloneWithOrWithoutBattery (asserts the fallback is standalone both with a synthetic Battery power_supply entry in a temp dir and without it) and TestOtherModesStaySelectableAndExplained. The Definition of Done is still open: it requires the interactive install path with the observed prompt recorded, which is being captured by the 464/465 real-install evidence run.

CONSEQUENCE EVIDENCE, 2026-10-08 (worker). The CURRENT cli/cmd/install_mode_suggestion_test.go (identical at 6c4786a18) was run at the fix parent 054611d1d^ = 059fafe59 in a scratch worktree. A compile-only shim, kept in tmp/464-evidence/465-parent-shim.diff, exposes the seams the test drives without changing behaviour: questionnairePrompt=prompt, installDomainLookup=publicDomainLookup, and installinput.SuggestedMode, which only the sibling test reads. The parent's installIsLaptop() and its development fallback are untouched.

RED at the parent, in a Linux container (golang:1.26-bookworm) with a battery presented at the REAL path, bind-mounting a dir with BAT0/type=Battery onto /sys/class/power_supply. Header: '## host: Linux x86_64; /sys/class/power_supply: BAT0 type=Battery'.
  --- FAIL: TestSuggestedModeIsStandaloneWithOrWithoutBattery
      --- FAIL: .../no_battery     install_mode_suggestion_test.go:102: suggested mode "development", want standalone
      --- FAIL: .../battery_present install_mode_suggestion_test.go:102: suggested mode "development", want standalone
(tmp/464-evidence/465-red-linux-battery.log)
GREEN at 6c4786a18, in the same container shape with the same battery mount ('## host: Linux aarch64; ... BAT0 type=Battery'): TestSuggestedModeIsStandaloneWithOrWithoutBattery PASS (both subtests), and TestOtherModesStaySelectableAndExplained PASS (development, private, standalone). See tmp/464-evidence/465-green-linux-battery.log.

FINDING, a limit of the test rather than a defect in the fix. The test's 'battery present' fixture is a temp tree that no code ever reads. The removed heuristic read the hard-coded /sys/class/power_supply, so the battery test is red at the parent ONLY when the HOST has a battery. Control: at the parent in the same container WITHOUT the mount ('/sys/class/power_supply: []'), both subtests PASS (tmp/464-evidence/465-parent-linux-no-battery.log). On macOS (no /sys) they also pass. So on battery-less CI this test would not catch a reintroduced host heuristic. The host-independent guard is TestOtherModesStaySelectableAndExplained. At the parent it FAILS on any host with 'field-table fallback "development" / SuggestedMode "standalone", want standalone', because AskWithMode's table fallback was development. That catches a non-standalone default, but not a future hardware check that reads the real /sys. Reported to the coordinator. No product change was made.

HOST-LEVEL OBSERVATION (DoD#2):
(1) This macOS laptop is a battery host ('pmset -g batt': InternalBattery-0 present). The real './sb install' at 6c4786a18, run on a PTY in a scratch clone with an isolated HOME, did NOT reach the questionnaire. It stopped in the fresh-install preflight with 'cannot check disk space at Docker storage: Docker root unavailable': Docker Desktop reports DockerRootDir=/var/lib/docker, which exists only inside its VM, and the host stat fails. The removed heuristic was also Linux /sys-only, so a macOS battery never influenced the suggestion. A macOS observation could not have shown the 465 battery case even without that block.
(2) A real interactive install.sh on a PTY, on a hardened Ubuntu 26.04 Hetzner VM (no battery: a cloud VM), printed exactly:
  Preparing a new StatBus installation.
    How will people reach StatBus?
      development: testing on this computer only
      standalone: this computer serves the public website on ports 80 and 443
      private: another web server forwards visitors to StatBus
    Deployment mode (development/standalone/private) [standalone]:
Pressing Enter installed CADDY_DEPLOYMENT_MODE=standalone. That proves the prompt text, the three explained modes and the standalone suggestion through the real install.sh, but on a host WITHOUT a battery.
NOT SHOWN, stated exactly: the real install.sh prompt observed on a Linux host that presents a battery. No such host was reachable, and the coordinator ruled out adding new VMs or machinery. The battery-host claim rests on the Linux-container red/green above: real /sys path, real runCreateConfig questionnaire through the prompt seam, no install.sh. DoD#1 is satisfied. DoD#2 is left unchecked for the owner to judge whether (2) plus the container red/green is sufficient.
<!-- SECTION:NOTES:END -->
