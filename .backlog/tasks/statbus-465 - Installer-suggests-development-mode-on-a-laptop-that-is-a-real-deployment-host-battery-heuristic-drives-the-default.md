---
id: STATBUS-465
title: >-
  Installer suggests development mode on a laptop that is a real deployment host
  (battery heuristic drives the default)
status: To Do
assignee: []
created_date: '2026-10-08 12:01'
labels:
  - installer
dependencies: []
priority: high
ordinal: 391204
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
NORTH STAR: the installer never nudges an operator toward a mode that only serves their own machine. The suggested default is standalone, and development is chosen deliberately with the consequences in front of them.

WHAT HAPPENS TODAY (verified in the code, 2026-10-08). Interactive installs call installinput.AskWithMode(prompt, modeDefault), and AskWithMode overrides the field table's own fallback for CADDY_DEPLOYMENT_MODE with the caller's modeDefault (cli/internal/installinput/config.go around lines 88-92). The caller sets modeDefault = "standalone", and switches it to "development" when installIsLaptop() reports true, which it decides by looking for an entry named BAT* whose type file reads Battery under /sys/class/power_supply (cli/cmd/install_host.go:15-30, called from cli/cmd/install.go:1750-1753). So the static "development" in the field table is normally inert, and the only way to see "[development]" is the battery heuristic firing.

THE FIELD EVIDENCE. The Finland installer log shows exactly that prompt defaulting to development on a machine whose hostname is PB14250, a Lenovo-style name, so the host really is a laptop. The operator accepted the default, and the resulting install is the self-hosting-only shape: local.statbus.org, the 3010/3011 port family, self-signed certificates. That is a large part of why the field then found the install confusing to reach and why the shorthand, protocol and port questions all came up.

WHY THIS IS THE WRONG NUDGE. The costs are asymmetric. If we wrongly suggest standalone on a developer's laptop, the cost is one re-run. If we wrongly suggest development on a deployment that was meant to serve a country, the operator ends up with a box that only serves itself and looks broken from the outside, which is precisely the support load this field report represents. Plenty of real deployments also run on laptop-class or mini hardware, so a battery is not evidence that the software is only for testing.

OPTIONS. (a) Default to standalone unconditionally and keep development as an explicit choice, with a line in the prompt telling a laptop user that development is for testing on this computer only. Simplest and matches the asymmetry. (b) Derive the mode from the domain answer, which requires asking the domain before the mode, because the field order today puts CADDY_DEPLOYMENT_MODE first and SITE_DOMAIN second (cli/internal/installinput/config.go:33-34); then a local.statbus.org or empty domain could suggest development. (c) Keep a hardware heuristic but make it stricter, for example battery AND no explicit public intent, which adds a rule for little gain. RECOMMENDATION: (a), plus setting the field table's own fallback to standalone so no code path can suggest development by accident.

SCOPE: installer prompt behaviour and its tests. Not the deployment modes themselves, and not the questionnaire wording beyond the one clarifying line.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 The installer does not suggest development as the default on a machine that is not the operator's own workstation; standalone is the default unless the operator explicitly chooses otherwise.
- [ ] #2 When a battery is detected, the prompt makes the consequence explicit (development serves this computer only; standalone serves the public site on ports 80 and 443) so the operator chooses knowingly instead of being nudged by hardware.
- [ ] #3 The field table fallback for CADDY_DEPLOYMENT_MODE is standalone, so no code path, interactive or not, can suggest development by accident.
- [ ] #4 A test covers both cases: battery present and battery absent, asserting the default each time.
<!-- AC:END -->

## Definition of Done
<!-- DOD:BEGIN -->
- [ ] #1 Verified through the interactive install path with the observed prompt recorded, not only by a unit test.
<!-- DOD:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Origin: the owner reviewing the Finland installer log on 2026-10-08 asked whether our default is development; the answer is that the code intends standalone and the battery heuristic made his laptop host default to development. Related field context: STATBUS-422.
<!-- SECTION:NOTES:END -->
