---
id: STATBUS-474
title: >-
  A real guest answers every setup question at its default and finishes a
  standalone country install
status: In Progress
assignee: []
created_date: '2026-10-08 15:16'
updated_date: '2026-10-08 21:08'
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
- [x] #1 0-interactive-setup-choices.sh presses Enter at the mode question and observes standalone as the default, with all three modes explained
- [x] #2 With a country-coded domain, the scenario presses Enter at the country name and code, observes the domain-derived suggestions, and the finished install has DEPLOYMENT_SLOT_NAME/DEPLOYMENT_SLOT_CODE set to that country, never StatBus/local
- [x] #3 The install completes and the site passes its health and HTTPS checks; the observed prompts are recorded in this ticket
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

2026-10-08 FIRST REAL RUN: GREEN, locally, in a fresh empty guest (no product or committed-script change).

WHY A GUEST AND NOT AN EMPTY DIRECTORY: the owner suggested running this "using an empty directory as a target". A plain macOS directory cannot work, because the installer's preflight needs Docker and systemd (the user unit, linger). An empty, freshly launched Ubuntu guest with no ~/statbus is the honest version of that suggestion. The scenario asserts that ~/statbus is absent before it starts.

TARGET: master tip 03f365be58de057b70eff11822adb344ab29a0af, which is untagged. Images run 37840071108 succeeded and published statbus-sb:03f365be. That image is a retag of 6d2ec4027 (the only differences 6d2ec4027..03f365be5 are under .backlog/), so the installed binary reports "sb version 6d2ec402 (commit 6d2ec402)". The checkout is 03f365be5.

HOW IT RAN (local, this Mac): the repository's own test/install-recovery/lib/vm-bootstrap.sh. It has been Hetzner-only since dad97fb8c retired the Multipass backend, so a throwaway shim tmp/474-local/bin/hcloud (not committed) answers the harness's hcloud create/ip/describe/delete calls with multipass. Everything else ran unchanged: the hardening (ops/setup-ubuntu-lts.sh), the statbus user with linger, the harness CA cert, /tmp/users.yml, and the candidate's own install.sh copied from the tree. Guest: multipass Ubuntu 26.04.1 LTS, aarch64, 4 CPU, 8G RAM, 30G disk. The image is cloud/server, not the Hetzner x86 image.
The scenario ran as a copy, tmp/474-local/0-interactive-setup-choices.local.sh. It differs from the committed 0385bfbc2 script only in its target lines:
(a) the target is TARGET_SHA plus install.sh --commit <sha> through SETUP_CHOICES_INSTALLER, instead of a release tag at HEAD with STATBUS_INSTALL_VERSION;
(b) EXPECTED_BINARY is the published image's version string;
(c) LIB_DIR/REPO_ROOT point at the repo.
The expect driver, the questions, the answers and every assertion are byte-identical.
Two deviations, both local only. The shim's cloud-init rewrites the guest's apt sources to https before hardening, because hardening's kernel.org mirror rewrite has no ubuntu-ports tree for arm64. The run also used KEEP_VM=1.
Duration: 11 min (launch 3.5 min, hardening, install ~4 min). Logs: tmp/474-local/run-20261008T225524.log, tmp/474-local/setup-choices-transcript.txt (raw PTY), tmp/install-recovery-statbus-recovery-0-interactive-setup-choices-64218-prompts.txt.

QUESTIONS EXACTLY AS PRINTED (PTY transcript, ANSI stripped, answer shown after the colon):
  Preparing a new StatBus installation.
    How will people reach StatBus?
      development: testing on this computer only
      standalone: this computer serves the public website on ports 80 and 443
      private: another web server forwards visitors to StatBus
    Deployment mode (development/standalone/private) [standalone]: <Enter>
  [1/18] Prerequisites OK  [2/18] Repository OK  [3/18] Program OK  [4/18] Configuration RUNNING
    The web address people will use. For local testing, use local.statbus.org.
    Domain name []: et.statbus-test.local
    et.statbus-test.local is not confirmed in public DNS, so an automatic public certificate cannot be promised, and local development is recommended for testing until the name is published and inbound port 80 is allowed.
    Which country does this installation serve? Its name is shown in the web interface, for example Norway.
    Suggested from the domain et.statbus-test.local; press Enter to accept it.
    Country name [Ethiopia]: <Enter>
    The country's code: two or three lowercase letters, used in container names and the subdomain, for example no for Norway.
    Suggested from Ethiopia; press Enter to accept it.
    Country code [et]: <Enter>
  [5/18] Credentials DONE  [6/18] Directories DONE
    Release signer to trust (GitHub username)
    Releases are signed; this names the GitHub user whose published signing key the installer verifies release tags against; jhf is the SSB release signer.
    StatBus recommends trusting the following release signer:
      jhf (Jorgen H. Fjeld) -- https://github.com/jhf
    256 SHA256:MU8OCWwTrZ6zkh0nZp/jmZpdgxe6rgBRDdlV87TqMIE no comment (ED25519)
  Trust key(s) from github.com/jhf? [Y/n] <Enter>
  [7/18] Trusted signers DONE ... [14/18] Seed DONE [15/18] Migrations OK [16/18] JWT secret DONE [17/18] Administrator DONE (1 user from /tmp/users.yml) [18/18] Upgrade service DONE
  Installation complete!
Driver count: mode=1 domain=1 country-name=1 country-code=1 signer=1. No re-asks, no warnings at the code, and no development, Email or unknown question.
The DNS notice after the domain is expected for a .local name. It is a notice, not a question, and the mode stayed standalone.

VALUES THAT ENDED UP IN THE CONFIGURATION (read from the guest):
  .env.config: CADDY_DEPLOYMENT_MODE=standalone, SITE_DOMAIN=et.statbus-test.local, DEPLOYMENT_SLOT_NAME=Ethiopia, DEPLOYMENT_SLOT_CODE=et, DEPLOYMENT_SLOT_PORT_OFFSET=1, POSTGRES_APP_DB=statbus_et, POSTGRES_APP_USER=statbus_et, BROWSER_REST_URL=https://et.statbus-test.local, UPGRADE_TRUSTED_SIGNER_jhf=<ssh-ed25519 key stored>
  .env: the same mode, domain, name and code, plus COMPOSE_INSTANCE_NAME=statbus-et and POSTGRES_APP_DB=statbus_et
  Containers: statbus-et-{app,db(healthy),proxy,rest,worker}.
Every answered value agrees with what was answered. Nothing is StatBus/local.

SITE AFTERWARDS: after `./sb cert install`, which printed "Verified: https://et.statbus-test.local serves the new certificate": health 200 on attempt 3, CA-verified HTTPS /rest/ 200, CA-verified HTTPS / 307 (the app's redirect), and statbus-upgrade@statbus.service active. Final line: "PASS: 0-interactive-setup-choices: Enter at every setup question installed standalone Ethiopia (et) at et.statbus-test.local".

ONE OBSERVATION FOR THE OWNER (not fixed here; it is not a question this ticket drives): .env.config and .env carry STATBUS_URL=http://localhost:3010 on this standalone et.statbus-test.local install. config.go:471 defaults it to "http://localhost:3010" whatever the mode or domain, while BROWSER_REST_URL is derived from the domain. Its only reader in cli/ is the upgrade callback (service.go:12383, passed as STATBUS_URL to UPGRADE_CALLBACK, e.g. ops/notify-slack.sh "Instance: <...>"). So a standalone box with a callback would announce itself as localhost:3010.

NOT CHANGED: the committed scenario (its header still says STATUS: UNRUN, and HARNESS_SKIP_DEFAULT stays as instructed), the default gate, and product code. The LXD-fleet run named in the precondition chain remains the owner's funding decision. This local run is the observation.
<!-- SECTION:NOTES:END -->
