---
id: STATBUS-468
title: >-
  Trusted signer added during install is not applied: .env lacks it, the
  completion banner contradicts the step, and the daemon refuses upgrades
status: In Progress
assignee: []
created_date: '2026-10-08 12:13'
updated_date: '2026-10-08 12:13'
labels:
  - installer
  - upgrade
dependencies: []
priority: high
ordinal: 394204
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
NORTH STAR: when the installer says a trusted signer was added, it is added, the generated .env carries it, the daemon loads it, and nothing later in the same run says otherwise.

THE OBSERVED CONTRADICTION (field log, 2026-10-08). Step 17/18 'Trusted signers' fetched the recommended signer jhf, the operator accepted the default [Y/n], and the step printed 'Added UPGRADE_TRUSTED_SIGNER_jhf to .env.config' followed by 'DONE'. Later in the SAME log, after 'Installation complete!', the installer printed 'No trusted signers configured (UPGRADE_TRUSTED_SIGNER_*) — upgrades will refuse to execute until at least one signer is added via: ./sb upgrade trust-key add <github-username>'.

THE MECHANISM (verified in the code). The trust-key adder writes .env.config: cli/cmd/upgrade.go:845-858 sets envKey := trustedSignerPrefix + username, f.Set(envKey, keys[0]), f.Save(), and prints 'Added %s to .env.config'. The reader, loadTrustedSigners in cli/internal/upgrade/service.go:5058-5097, reads UPGRADE_TRUSTED_SIGNER_* from the generated .env and prints the no-signer banner when it finds none. The install step table runs 'Trusted signers' (cli/cmd/install.go:1154) after configuration was generated earlier in the same run, and nothing regenerates .env after the signer write, so both the completion banner and the daemon see the pre-signer .env.

IMPACT, which is not cosmetic: the box finishes with an upgrade daemon whose .env has no trusted signer, so automatic upgrades refuse to execute even though the operator accepted the recommended signer, and the completion output contradicts itself in the same screen.

THIS IS THE STATBUS-332 CLASS: every .env.config key needs a regenerate and restart (and, where values are interpolated into compose, a recreate rather than a restart) to take effect. The signer step must apply its change the way other configuration changes do, before the completion banner and before the final daemon start.

REQUIRED BEHAVIOUR.
1. After the trust step, apply the configuration so the generated .env contains the signer and the consuming services are recreated or restarted as the apply mechanism requires, before the banner and before the daemon start.
2. The completion output must agree with reality: with a signer configured and applied, it never prints the no-signer warning.
3. The daemon must actually have the signer on its next start, provable through the trust loading it performs (the allowed_signers content or equivalent).
4. If applying the signer fails, the installer reports that truthfully instead of printing 'Added ... to .env.config' and then denying it.
5. A test asserts the end state and fails against today's behaviour.

EVIDENCE TO RECORD: from a real install or the closest integration path, the UPGRADE_TRUSTED_SIGNER_ line in the generated .env, the absence of the no-signer banner, and the signer visible to the daemon's trust loading.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 After an install that accepts the recommended signer, the generated .env contains UPGRADE_TRUSTED_SIGNER_<name> and the completion output does not print the no-signer warning.
- [ ] #2 The upgrade service loads that signer on its next start, asserted through the trust loading it performs (allowed_signers content or equivalent).
- [ ] #3 The signer step applies its change through the same regenerate and recreate path that other .env.config changes use, so the writer and the reader cannot disagree.
- [ ] #4 A test asserts that end state and fails against today's behaviour, which prints the contradiction.
- [ ] #5 If applying the signer fails, the installer says so truthfully instead of claiming the key was added and then reporting that none is configured.
<!-- AC:END -->

## Definition of Done
<!-- DOD:BEGIN -->
- [ ] #1 Evidence from a real install, or the closest integration path available, is recorded in the ticket: the .env line, the absent banner, and the daemon's loaded signers.
<!-- DOD:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Owner report 2026-10-08: this is very strange and incorrect. Origin: the Finland install log, where step 17 reported the signer added and the completion banner reported none configured. Related precedent for the class: STATBUS-332, the config-apply gap where every .env.config key needs regenerate-and-restart (and recreate for compose interpolation) to take effect.
<!-- SECTION:NOTES:END -->
