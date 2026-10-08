---
id: STATBUS-474
title: >-
  A real guest answers every setup question at its default and finishes a
  standalone country install
status: In Progress
assignee: []
created_date: '2026-10-08 15:16'
updated_date: '2026-10-08 16:56'
labels:
  - install
  - installer
  - test
dependencies:
  - STATBUS-466
priority: medium
ordinal: 400204
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
NORTH STAR: the interactive setup questions (mode, domain, country name, country code; STATBUS-400/466) are proven in a real Ubuntu guest through install.sh, not only by unit tests and a PTY run of the binary.

WHY THIS TICKET EXISTS: STATBUS-400 AC2 named test/install-recovery/scenarios/0-interactive-setup-choices.sh. As written it asked the installer to detect a private laptop and default to development, which the owner decision in STATBUS-465 (commit 054611d1d) reversed: the installer always suggests standalone. 3a87b058e (STATBUS-466) landed the questions and observed them with the real ./sb install on a PTY in a Linux container (tmp/statbus-466-observed/interactive-prompts.txt), stopping at Credentials because that sandbox has no database. No LXD-fleet scenario has driven those questions end to end in a hardened guest. Per doc/install-upgrade-testing.md, only a real run says whether they work there.

WHAT TO DO: add 0-interactive-setup-choices.sh on the LXD fleet, modelled on 0-interactive-admin-password.sh (expect on a PTY). Drive the Configuration questions with Enter at the mode, a domain whose first label is a country code, and Enter at the country name and code, then finish the install and assert .env.config and the running site.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 0-interactive-setup-choices.sh presses Enter at the mode question and observes standalone as the default, with all three modes explained
- [ ] #2 With a country-coded domain, the scenario presses Enter at the country name and code, observes the domain-derived suggestions, and the finished install has DEPLOYMENT_SLOT_NAME/DEPLOYMENT_SLOT_CODE set to that country, never StatBus/local
- [ ] #3 The install completes and the site passes its health and HTTPS checks; the observed prompts are recorded in this ticket
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
2026-10-08 scenario written, UNRUN (STATBUS-474).

What landed:
- 0385bfbc2 test/install-recovery/scenarios/0-interactive-setup-choices.sh. This is the scenario itself.
- e1387ff48 test/install-recovery/lib/lxd-backend.sh adds one slug to lxd_checkpoint_for_scenario's fresh-install case list. The change is ADDITIVE ONLY: I ran the real resolver over all 32 scenario slugs before and after, and only this slug changed, from installed-v2026.09.3-standalone to hardened-nothing-installed. Every other slug resolves exactly as before.

What the script drives: the candidate's own install.sh on a PTY via expect. There is no answers file. STATBUS_USERS_FILE is supplied so the administrator questions stay out of this run. Each question is matched by its own words, never by its position:
- Deployment mode: Enter. Asserts the suggestion is standalone and that development, standalone and private are all explained.
- Domain name: et.statbus-test.local.
- Country name: Enter. Asserts the suggestion says "Suggested from the domain et.statbus-test.local" and is Ethiopia.
- Country code: Enter. Asserts the suggestion is et, says "Suggested from Ethiopia", and is accepted without a re-ask or warning.
- Release signer: Enter for jhf.
Anything else fails and is named: a development question, the Email question, any unknown [..]: or [y/n] question, a FAILED step, the installer exiting non-zero, or a missing "Installation complete!". Every wait is bounded: 900s with no question or step line before the signer answer, 1800s with no step line after it. On failure it prints what it expected and what arrived, and how many times each question was asked. The questions as shown are saved to tmp/install-recovery-<vm>-prompts.txt for this ticket's AC#3 record.

Country choice: the name is not hard-coded. It is read at run time from dbseed/country/country_codes.csv, the seed that installinput/countries_table.go is generated from (TestCountryTableMatchesSeed keeps them identical). ET maps to Ethiopia. Ethiopia is a real SSB slot, and its code is two letters, which the domain rule requires.

End-state assertions:
- .env.config: CADDY_DEPLOYMENT_MODE=standalone, SITE_DOMAIN, DEPLOYMENT_SLOT_NAME=Ethiopia, DEPLOYMENT_SLOT_CODE=et, UPGRADE_TRUSTED_SIGNER_jhf stored.
- .env: the same values plus COMPOSE_INSTANCE_NAME=statbus-et and POSTGRES_APP_DB=statbus_et.
- Containers statbus-et-{db,rest,app,worker,proxy} are running.
- ./sb --version equals the candidate.
- After `./sb cert install` of the harness CA-signed cert: assert_health_passes, assert_harness_https_passes, CA-verified HTTPS on /, and assert_systemd_active.
Every mismatch is printed as expected versus arrived.

Harness assumptions, stated in the script header:
(1) The questionnaire does not ask for a certificate (STATBUS-399). install.sh therefore stages the harness cert files through STATBUS_HARNESS_CERT_STAGING as every harness standalone install does, and the scenario selects them with `./sb cert install` before checking HTTPS.
(2) The LXD base issues its CA cert for statbus-test.local only. The scenario re-issues the domain cert from the harness CA for et.statbus-test.local and adds the /etc/hosts line. On Hetzner, HARNESS_SITE_DOMAIN already makes bootstrap do this.

Offline checks done:
- bash -n and shellcheck -x are clean.
- The embedded expect driver was run locally against a fake installer that replays the prompt text recorded in tmp/statbus-466-observed. The GOOD run passes. Five broken variants each fail with a legible message: mode default development, wrong country suggested, an unexpected question, installer exit 3, and 5s of silence.
- Catalogue: `run.sh --list` shows the slug as "[on-demand only, excluded from default run]". It is absent from the default `--print-selected` and selected by its slug or the 0- phase prefix.
- Harness selftests pass after the case-list change: vm-image-selection, lxd-checkpoint-identity, scenario-selection, lxd-default-domain, lxd-bootstrap-discriminator, lxd-staging-path. No selftest pins each slug's checkpoint, so none covers this slug's mapping specifically. The before/after resolver diff above is the evidence for that.

Why it is UNRUN: the first real guest run is a funding decision about the scenario catalogue's CI cost, and it is the owner's. HARNESS_SKIP_DEFAULT keeps it inert: run.sh:33 sets the marker and lxd/run-forks.sh:104 skips any script containing it. Until then it adds no cost to the default RC fault gate.

Precondition chain for the Definition of Done (the real run):
(a) slug registration, done in e1387ff48;
(b) the owner's funding decision;
(c) `test/install-recovery/lxd/run-forks.sh <candidate-tag> --scenario 0-interactive-setup-choices` on a candidate tagged at or after e1387ff48.
Then record the observed prompts here, check the ACs, and remove HARNESS_SKIP_DEFAULT if the owner adds it to the default catalogue. Not Done until that run is green.

2026-10-08 CI for e1387ff48 (pushed together with 0385bfbc2):
- Harness Selftest 37811621273: success. Go Test 37811621249, Fast Tests 37812148315, app build and lint 37811621289, CodeQL 37811621416, Notify 37811621232: all success.
- Images 37811621235: FAILURE, in the seed job only. All image builds and manifests succeeded.

The cause is not this ticket's change (harness files only). The incremental seed build restored the prior master seed (depth 2 -> 3, the dump built at f0486e266 on top of a64f4ad38/STATBUS-460). pg_restore died on REVOKE ALL ON FUNCTION public.upgrade_schedule(...) because health_checks() raised "cannot revoke MAINTAIN directly from establishment__for_portion_of_valid, revoke MAINTAIN from establishment instead". The depth 1 -> 2 builds at a64f4ad38 and f0486e266 succeeded. The first dump containing the STATBUS-460 state is the one that cannot be restored. Reported to the coordinator as a separate product finding. Every subsequent master push will hit it until fixed.
<!-- SECTION:NOTES:END -->
