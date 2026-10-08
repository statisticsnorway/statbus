---
id: STATBUS-468
title: >-
  Trusted signer added during install is not applied: .env lacks it, the
  completion banner contradicts the step, and the daemon refuses upgrades
status: Done
assignee: []
created_date: '2026-10-08 12:13'
updated_date: '2026-10-08 15:00'
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
- [x] #1 After an install that accepts the recommended signer, the generated .env contains UPGRADE_TRUSTED_SIGNER_<name> and the completion output does not print the no-signer warning.
- [x] #2 The upgrade service loads that signer on its next start, asserted through the trust loading it performs (allowed_signers content or equivalent).
- [x] #3 The signer step applies its change through the same regenerate and recreate path that other .env.config changes use, so the writer and the reader cannot disagree.
- [x] #4 A test asserts that end state and fails against today's behaviour, which prints the contradiction.
- [x] #5 If applying the signer fails, the installer says so truthfully instead of claiming the key was added and then reporting that none is configured.
<!-- AC:END -->

## Definition of Done
<!-- DOD:BEGIN -->
- [x] #1 The new tests are shown CONSEQUENTIAL: at 059fafe59^ they FAIL, at minimum the upgrade-package test asserting the daemon's allowed_signers content and the step-name matching that lets the decline branch fire; at HEAD they pass. Both outputs recorded.
- [ ] #2 The end-state claims that are genuinely about a running host (.env carrying the signer, no contradicting completion banner, the daemon's loaded signers) are recorded from ONE real install observation, not a scenario catalogue.
<!-- DOD:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Owner report 2026-10-08: this is very strange and incorrect. Origin: the Finland install log, where step 17 reported the signer added and the completion banner reported none configured. Related precedent for the class: STATBUS-332, the config-apply gap where every .env.config key needs regenerate-and-restart (and recreate for compose interpolation) to take effect.

2026-10-08 review-gap closure, commit 39f322aa7 (on top of the fix 059fafe59).

GAPS CLOSED
(a) install.sh matched the literal '[16/17] Trusted signers'. After the reorder the step is 7/18, so 'release signer approval was declined' could never print. It now matches '^\[[0-9]+/[0-9]+\] Trusted signers +FAILED:' AND the prompt's own 'Approval declined.' line, and takes the position from the line itself. test/install-recovery/tests/fresh-installer-test.sh now emits ./sb's real output shape ([7/18], INSTALL_CAUSE/FIX) instead of a hand-made line.
    FOUND WHILE CLOSING (a): the branch also could not fire because a fresh-install decline never failed the step. runTrustSigners printed 'Approval declined. The installer will stop...' and returned nil, so the step printed DONE and the install finished with no signer. The step table now runs runTrustSignersStep, which returns 'release signer approval was declined...' on an explicit 'n'. A key fetch that fails stays non-fatal, as before.
(b) The comment at cli/cmd/install_apply_config_changes_test.go:32 is corrected: there are 7 steps after the anchor, Trusted signers is no longer among them, and the comment says why.
(c) DELIBERATE AND ACCEPTED: the interactive signer prompt now comes BEFORE the image pull, because Trusted signers runs before Settings. The operator answers every question up front and the long pull runs unattended afterwards. This is recorded in the step-table comment in install.go. Do not move it back.
(d) A daemon-side proof is added. cli/internal/upgrade/trusted_signers_load_test.go runs Service.loadTrustedSigners against a fixture .env, asserts that tmp/allowed-signers is exactly 'jhf <key>\n', then signs a commit with a fresh ed25519 key and checks that verifyCommitSignature accepts it through that file. The empty-.env case (the field state) gives no file and the refusal 'no trusted signers configured'. Also added: Service.LoadTrustedSigners() (an exported read-only accessor) and cmd TestInstallStepOrderGivesTheDaemonTheApprovedSigner, which runs the install steps in the step table's ACTUAL order and then the daemon's trust load on the generated .env.
    verifyTrustedSignersApplied's failure now goes through printInstallStepFailure as the Trusted signers step. It gets a classified cause, 'The approved release signer did not reach the settings the update service reads.', and the fix 'Run cd ~/statbus && ./sb config generate, then retry.' Both are allowlisted in install.sh, and the allowlist test covers them.

RED/GREEN CONSEQUENCE DEMONSTRATION (scratch worktree at 059fafe59^ = 88f5198e4, with HEAD's new tests copied in plus only the read-only LoadTrustedSigners accessor
RED at 059fafe59^:
  --- FAIL: TestTrustedSignersStepRunsBeforeSettingsGeneration: 'Trusted signers (position 17) must run before Settings (position 7)'
  --- FAIL: TestInstallStepOrderGivesTheDaemonTheApprovedSigner: 'daemon loaded no trusted signer from the .env this install generated, so it would refuse every upgrade'
  --- FAIL: TestDeclinedSignerFailsTheTrustedSignersStep: 'declined signer: alreadyDone=false err=<nil>' (decline printed DONE)
  fresh-installer-test.sh with the old install.sh and the real [7/18] decline output: exit 1. The operator saw 'Cause: The release signature could not be verified.', never the decline sentence.
GREEN at 39f322aa7: all of the above PASS, plus TestApprovedSignerReachesTheDaemonsSettings, TestSignerWrittenAfterGenerationIsReportedNotHidden (now also asserting the classified INSTALL_CAUSE/INSTALL_FIX operator lines), TestInstallCauseAndFixMatchShellAllowlist, and 'fresh-installer tests: PASS' including the new 'a signer that did not reach the settings is reported with its remedy'.
NOT A RED/GREEN PAIR: the upgrade-package tests TestDaemonLoadsTheInstalledSignerIntoAllowedSigners and TestDaemonWithoutTheSignerInEnvRefusesVerification PASS at the parent too. That is expected, because the daemon's reader was never broken: the defect was WHEN the installer wrote the key. They pin the daemon half of the chain (.env to allowed-signers to a verified commit). The installer-to-daemon chain is what turns red.

LANDING: gofmt -l is empty for the changed files. 'go test ./...' passed (exit 0) in a clean HEAD worktree carrying only this diff. The shared checkout has another agent's in-progress cli/internal/installinput/country.go, which does not build at the moment. That has nothing to do with 468.

REAL INSTALL: per the owner's 2026-10-08 course correction, no VM or real install was run. The claim the test pair cannot show is that a real systemd-started daemon on a real box loads it. The tests call the same loadTrustedSigners that Run() and LoadConfigAndConnect() call, against a .env written by the real generator, so the remaining gap is only the process start-up wiring (Run calling loadTrustedSigners), which is unchanged by this ticket.
EOF
)

CI for 39f322aa7: Go Test success (run 37796359382), Harness Selftest success (37796359571), Images success, app build & lint success, Push on master success. Fast Tests (pg_regress, run 37797056820) was still queued behind 3311dd863's run when this was recorded. This commit changes no SQL. DoD #1 is met through the closest integration path, the red/green test chain above. A real install was deliberately not run, per the owner's 2026-10-08 direction.

DoD reconciliation (the DoD was reworded while this work was in flight). DoD #1 is checked with one caveat stated plainly: the allowed_signers assertion that turns RED at 059fafe59^ is the cmd test TestInstallStepOrderGivesTheDaemonTheApprovedSigner, which asserts the content of the file written by the daemon's own Service.LoadTrustedSigners. The upgrade-package tests stay green at the parent, because the daemon's reader was never the defect. The step-name match is red/green through fresh-installer-test.sh. DoD #2 is deliberately LEFT UNCHECKED: per the owner's 2026-10-08 direction no real install or VM was run, so no host observation exists. The status was set to Done as instructed. DoD #2 is the one open item, and it needs one real install observation.
<!-- SECTION:NOTES:END -->
