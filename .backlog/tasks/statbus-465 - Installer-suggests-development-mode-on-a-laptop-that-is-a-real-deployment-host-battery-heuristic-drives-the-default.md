---
id: STATBUS-465
title: >-
  Installer suggests development mode on a laptop that is a real deployment host
  (battery heuristic drives the default)
status: Done
assignee: []
created_date: '2026-10-08 12:01'
updated_date: '2026-10-08 15:57'
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
- [x] #1 The deployment-mode suggestion is the compile-time constant SuggestedMode = standalone: both the interactive prompt's fallback and the value installinput.Ask suggests are that constant, asserted by cli/cmd/install_mode_suggestion_test.go, while development and private remain selectable with their explanations. Running the installer IS the standalone installation, by owner decision.
- [x] #2 TestModeSuggestionIsTheSuggestedModeConstant is shown CONSEQUENTIAL: at 054611d1d^ (which still had the development fallback in the field table) it FAILS on any host, battery or not, and at HEAD it passes, with both outputs recorded in the ticket. This supersedes the earlier battery-fixture evidence, which could not fail on battery-less CI.
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

CLOSED per the owner's point (2026-10-08): the battery heuristic is REMOVED, so there is nothing host-derived left to observe. Verified read-only: rg finds no power_supply, Battery, /sys or installIsLaptop reference in cli/ or install.sh outside tests, and cli/internal/installinput/config.go documents and uses the constant SuggestedMode = 'standalone'. The earlier DoD#2 (an observation on a host presenting a battery) asked for evidence of a behaviour that no longer exists; the consequential test remains DoD#1 (the suggestion test fails at 054611d1d^ and passes at HEAD).

DoD reworked (2026-10-08, owner's point): a test that asserts removed code is ABSENT is not a real invariant, so the criterion now asserts the positive behaviour - the suggestion IS the constant SuggestedMode and the prompt falls back to it - which is what the test checks, and DoD#1 now names the renamed test (TestModeSuggestionIsTheSuggestedModeConstant, commit ac2c7b866) instead of the deleted battery-fixture test.

DoD state: item #1 (the suggestion IS the constant, asserted by the test and by installinput.Ask's fallback) is verified and checked. Item #2 (the renamed test shown failing at 054611d1d^ and passing at HEAD) stays OPEN until vole records those two outputs; the code change is landed (ac2c7b866) but the red output for the renamed test has not been pasted in yet.

## 2026-10-08: battery fixture replaced by the constant assertion (ac2c7b866). This supersedes the battery-fixture evidence.

Commit ac2c7b866 changes only cli/cmd/install_mode_suggestion_test.go. It removes TestSuggestedModeIsStandaloneWithOrWithoutBattery: that test fabricated a temp sys/class/power_supply tree, but the removed installIsLaptop read the hard-coded /sys/class/power_supply, so the fixture never reached the code it claimed to test and could not fail on battery-less CI. In its place, TestModeSuggestionIsTheSuggestedModeConstant asserts three things: SuggestedMode == standalone, installinput.Ask offers SuggestedMode, and the installer's interactive Configuration step (runCreateConfig) offers SuggestedMode and pressing Enter configures it. TestOtherModesStaySelectableAndExplained is kept: development and private stay selectable and explained, and the suggestion does not move. Nothing about the host is read or faked. No product code under cli/ references power_supply, Battery or /sys/class; the remaining "laptop" words are comments in unitfloor/config/testgit.

### RED at 054611d1d^ (= 059fafe59)
Run in a scratch git worktree on jhf's Mac (arm64, no battery-shaped /sys at all; Go only, no database). The parent cannot compile the cleaned test, so these declaration-only shims were added:
- installinput: the constants SuggestedMode="standalone" (the value the test claims, so the shim cannot mask the parent), CountryNamePrompt/CountryCodePrompt/DevelopmentNamePrompt/DevelopmentCodePrompt.
- cmd: the two seams 054611d1d itself introduced (questionnairePrompt = prompt, installDomainLookup = publicDomainLookup), routed exactly as 054611d1d routes them, plus the test helper countryAnswer.
The parent's Ask/AskWithMode, its field table (CADDY_DEPLOYMENT_MODE fallback "development") and installIsLaptop are untouched. The failing assertion is on installinput.Ask, which reads no host state at all, so it fails on any host, battery or not.
```
=== RUN   TestModeSuggestionIsTheSuggestedModeConstant
    install_mode_suggestion_test.go:103: installinput.Ask suggests "development", want SuggestedMode "standalone"
--- FAIL: TestModeSuggestionIsTheSuggestedModeConstant (0.00s)
=== RUN   TestOtherModesStaySelectableAndExplained
=== RUN   TestOtherModesStaySelectableAndExplained/development
=== RUN   TestOtherModesStaySelectableAndExplained/private
=== RUN   TestOtherModesStaySelectableAndExplained/standalone
--- PASS: TestOtherModesStaySelectableAndExplained (0.01s)
FAIL
FAIL	github.com/statisticsnorway/statbus/cli/cmd	0.507s
FAIL
```
### GREEN at HEAD (ac2c7b866), same Mac, real checkout
```
=== RUN   TestModeSuggestionIsTheSuggestedModeConstant
--- PASS: TestModeSuggestionIsTheSuggestedModeConstant (0.01s)
=== RUN   TestOtherModesStaySelectableAndExplained
=== RUN   TestOtherModesStaySelectableAndExplained/development
=== RUN   TestOtherModesStaySelectableAndExplained/private
=== RUN   TestOtherModesStaySelectableAndExplained/standalone
--- PASS: TestOtherModesStaySelectableAndExplained (0.01s)
ok  	github.com/statisticsnorway/statbus/cli/cmd	0.548s
```
### CI for ac2c7b866
- Go Test 37803293000: success (cli go test ./... success, cli golangci-lint success).
- Images, app build & lint, Harness Selftest, Push on master and Notify: all success.
- Fast Tests (pg_regress) was superseded by later master pushes. This change has no SQL.
<!-- SECTION:NOTES:END -->
