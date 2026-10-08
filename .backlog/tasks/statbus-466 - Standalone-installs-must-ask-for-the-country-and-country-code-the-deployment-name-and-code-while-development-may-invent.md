---
id: STATBUS-466
title: >-
  Standalone installs must ask for the country and country code (the deployment
  name and code), while development may invent
status: Done
assignee: []
created_date: '2026-10-08 12:07'
updated_date: '2026-10-08 15:16'
labels:
  - installer
dependencies: []
priority: high
ordinal: 392204
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
NORTH STAR: a standalone installation asks the operator which country it serves and what its country code is, because those two answers ARE the deployment name and the deployment code in our design. A local development installation may invent both. Nobody has to guess.

WHAT THE PROMPTS SAY TODAY (cli/internal/installinput/config.go, verified 2026-10-08). The field table lines 33-36 hold CADDY_DEPLOYMENT_MODE (default development), SITE_DOMAIN (empty), DEPLOYMENT_SLOT_NAME (prompt 'Display name', default 'StatBus') and DEPLOYMENT_SLOT_CODE (prompt 'Deployment code (short, lowercase)', default 'local'). AskWithMode adds the guidance lines: for the code, 'A short lowercase name for this installation (used in container names).'; for the name, 'A name people will recognize in the web interface.'. There is no validation of the code anywhere: no shape check, no country awareness. So an operator running the official installer and pressing Enter on both questions ends up with the name 'StatBus' and the code 'local'.

WHAT THE DESIGN ACTUALLY IS. Our own slots are country and territory codes: doc/CLOUD.md's slot table lists no, pk, et, jo, ma, ug and the torn-down tcc, each with its own subdomain, container-name prefix and port offset. DEPLOYMENT_SLOT_NAME is the country name people see in the interface; DEPLOYMENT_SLOT_CODE is the lowercase country code used in container names and the subdomain. 'StatBus' and 'local' are development values, not production ones.

REQUIRED BEHAVIOUR.
1. For a standalone installation the questions ask the real question: which country this installation serves, that is the name shown in the interface, and its country code, short and lowercase, used in container names and the subdomain, with examples such as Norway and no.
2. The standalone suggestion must not be the development default. Derive the suggested code from the domain answer where that is meaningful, the first label of the hostname, and never silently accept 'local' or 'StatBus' in standalone.
3. Validate the code's shape, short lowercase letters, and warn when it does not look like a country code, without blocking: a deliberate test installation must be able to proceed, with the escape hatch explained rather than hidden.
4. Development keeps the permissive behaviour and the invented defaults, because inventing is what a local install is for.
5. Tests cover standalone with country-shaped answers, development with invented answers, and the press-Enter path for each, so the development defaults cannot leak into a standalone install unnoticed.

OUT OF SCOPE: the deployment mode default (STATBUS-465) and user provisioning (STATBUS-464), both in flight.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 In a standalone installation the prompts ask for the country name shown in the interface and the country code used in container names and the subdomain, with concrete examples, and the rendered prompts are observed to say so.
- [x] #2 Pressing Enter through a standalone install never silently yields the development defaults StatBus and local; the standalone suggestion comes from a real signal such as the domain answer, or entry is required.
- [x] #3 The country code is validated for shape, short and lowercase, and a value that does not look like a country code produces a warning while an explained path lets a deliberate test installation proceed.
- [x] #4 Development keeps its permissive prompts and invented defaults.
- [x] #5 Tests cover standalone country-shaped answers, development invented answers, and the press-Enter path for both, and the standalone case is verified through the interactive install path with the observed prompts recorded.
<!-- AC:END -->

## Definition of Done
<!-- DOD:BEGIN -->
- [x] #1 The observed prompts for a standalone run and for a development run are recorded in the ticket, not only asserted in tests.
<!-- DOD:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
## Landed 3a87b058e (2026-10-08), takeover of the uncommitted WIP

The seven findings from the takeover review in Comments #1, each against 3a87b058e:
1. No real default for the country name: FIXED. The name is suggested only from a real signal, with the reason shown: the domain's first label (no.statbus.org), its country TLD (statbus.ssb.no, generic .io/.co/.ai/.me/.tv/.fm excluded), or the host time zone (zone.tab). With no signal, entry is required and an empty answer is re-asked (AC2's "or entry is required"). The code is suggested from the chosen country.
2. Shape check instead of the real country list: FIXED. The list is dbseed/country/country_codes.csv, embedded as countries_table.go and held identical by TestCountryTableMatchesSeed.
3. Private mode still got StatBus/local: FIXED. Every mode except development asks for the country (TestPrivateAsksForTheCountry).
4. A development code derived from my-laptop aborted the install: FIXED. An unusable label falls back to local, and a malformed code is re-asked (TestDevelopmentInventsNameAndCode).
5. No advice for an unattended non-country code: FIXED. AnswerAdvice prints a non-blocking note (observed below).
6. TestSetupChoiceExplanationsAndDefaults failed, and the doc table said Display name: FIXED. The test passes at 3a87b058e. doc/DEPLOYMENT.md's table says Country name/Country code, with a Norway example, held by TestDeploymentDocumentationUsesExactQuestionnaire.
7. No recipe assertion and no observed prompts: FIXED. TestRecipeShowsCountryValuesNotDevelopmentValues covers the recipe, and the observed prompts are below.

### Red/green (host: jhf's Mac, Go only; no database is involved, these are pure Go unit tests)
RED at parent d47b17abf: an export of d47b17abf plus the new test files from 3a87b058e. Without a shim it does not compile (`config_test.go:15:32: undefined: CountryNamePrompt`). A compile-only shim (zz_red_shim.go) declares only the missing names and leaves the parent's Ask/Requirement/parse untouched. With it, per test:
- FAIL TestSetupChoiceExplanationsAndDefaults: defaults: mode "standalone" domain "" name "" code ""
- FAIL TestRecipeShowsCountryValuesNotDevelopmentValues: recipe lacks "DEPLOYMENT_SLOT_NAME=Norway  # Country name", and recipe shows development value "=StatBus" and "=local"
- FAIL TestCountryTableMatchesSeed: seed has 251 countries, installer table 0
- FAIL (panic) TestStandaloneCountryAnswers, TestStandalonePressEnterUsesRealSignals, TestStandalonePressEnterWithoutSignalRequiresEntry, TestPrivateAsksForTheCountry, TestCountryCodeWarningHasExplainedEscapeHatch, TestModeQuestionReasksUnknownAnswers: "unexpected question: A name people will recognize in the web interface." The parent asks the development question in standalone and private.
- FAIL TestDevelopmentInventsNameAndCode (development questions lack the "may invent" explanation), TestUnattendedAnswerAdviceAndRefusals (private + code test: advice ""), TestZoneCountry (shim: no lookup)
- ok: the 4 pre-existing tests (same set, required keys, refusals, doc, trust)
GREEN at 3a87b058e (an export of the commit): all 16 installinput tests ok. The cli/cmd installer tests are ok in the real checkout at 9d384630d (installinput is unchanged since 3a87b058e). go test ./... (24 packages ok), go vet, gofmt and golangci-lint all report 0 issues.
Logs: tmp/statbus-466-observed/{red-per-test.txt,green-per-test.txt,red-at-d47b17abf.log,go-test-all.log}

### Observed prompts (DoD #1, AC1, AC5): the real ./sb install on a PTY
Host: Linux arm64 container docker:cli on jhf's Mac, with the Docker socket mounted, run as a non-root user `op` in a sandbox checkout at /home/op/statbus. The binary is sb built from the 3a87b058e tree with commit ldflags, and expect drives the real installer. There is no database: it stops at Credentials, after the questions. Full transcripts: tmp/statbus-466-observed/interactive-prompts.txt and unattended-recipe-and-advice.txt.

Standalone, Enter everywhere, TZ=Africa/Addis_Ababa:
```
  Deployment mode (development/standalone/private) [standalone]:
  The web address people will use. For local testing, use local.statbus.org.
  Domain name []: statbus.example.org
  Which country does this installation serve? Its name is shown in the web interface, for example Norway.
  Suggested from this computer's time zone Africa/Addis_Ababa; press Enter to accept it.
  Country name [Ethiopia]:
  The country's code: two or three lowercase letters, used in container names and the subdomain, for example no for Norway.
  Suggested from Ethiopia; press Enter to accept it.
  Country code [et]:
-> .env.config: CADDY_DEPLOYMENT_MODE=standalone, DEPLOYMENT_SLOT_NAME=Ethiopia, DEPLOYMENT_SLOT_CODE=et (POSTGRES_APP_DB=statbus_et)
```
Standalone, domain no.statbus.org, deliberate test code, TZ=UTC:
```
  Suggested from the domain no.statbus.org; press Enter to accept it.
  Country name [Norway]:
  Country code [no]: test
  "test" is not a country code (two or three letters from ISO 3166, such as no for Norway).
  For a deliberate test installation, press Enter to keep test. Otherwise type the country code.
  Country code [test]:
-> DEPLOYMENT_SLOT_NAME=Norway, DEPLOYMENT_SLOT_CODE=test
```
Standalone, no signal (statbus.example.org, TZ=UTC): `Country name []:`, then Enter re-asks with "Please type the country name people will see, for example Norway." No development value is offered.
Development, Enter, TZ=Europe/Oslo:
```
  A name people will recognize in the web interface. A development installation may invent one.
  Display name [StatBus]:
  A short lowercase name for this installation, used in container names. A development installation may invent one.
  Deployment code (short, lowercase) [local]:
-> DEPLOYMENT_SLOT_NAME=StatBus, DEPLOYMENT_SLOT_CODE=local
```
Unattended recipe (`./sb install --non-interactive`, no STATBUS_ENV_CONFIG):
```
  DEPLOYMENT_SLOT_NAME=Norway  # Country name
  DEPLOYMENT_SLOT_CODE=no  # Country code
```
Unattended standalone answer file with DEPLOYMENT_SLOT_CODE=test prints: `Note: DEPLOYMENT_SLOT_CODE=test. "test" is not a country code (...). A standalone installation serves one country, so its code is normally that country's code. Continuing with "test" as given.` Configuration then finishes DONE.

### CI for 3a87b058e
Go Test 37798000729 success (cli go test ./... success, cli golangci-lint success). Images, app build & lint, Harness Selftest, Push on master and Notify all succeeded. Fast Tests 37798302826 for this SHA was cancelled by later master pushes (cancel-in-progress). It is pg_regress, and this change touches no SQL.
<!-- SECTION:NOTES:END -->

## Comments

<!-- COMMENTS:BEGIN -->
created: 2026-10-08 14:27
---
Takeover review of the uncommitted WIP (2026-10-08, copy in tmp/other-session-wip-20261008/). COMPLETE in the WIP: standalone asks 'Country name' and 'Country code' with Norway/no examples (AC1 wording); the unattended recipe shows example.org/Norway/no via RecipeExample; a hard code-shape rule (lowercase letters+digits, starts with a letter, at most 20) in both the interactive and the unattended path; a non-blocking 'does not look like a country code' warning whose Enter keeps a deliberate test code (AC3 escape hatch); development keeps StatBus/local (AC4). MISSING: (1) the country name has NO default at all, and the code default only exists for a two-letter first domain label, so most press-Enter runs end with an empty answer and a validation failure rather than a real default; (2) 'looks like a country code' is just 'two or three letters', not a real country list; the repo already has one (dbseed/country/country_codes.csv); (3) private mode (our own cloud country slots, doc/CLOUD.md) still gets the development values StatBus/local; (4) the development code question can derive an invalid code from the domain (e.g. my-laptop) that the new hard rule then rejects, aborting the install instead of re-asking; (5) an unattended standalone file with a non-country code gets no advice; (6) TestSetupChoiceExplanationsAndDefaults fails on the WIP; the doc/DEPLOYMENT.md prompt table still says 'Display name'; (7) no test asserts the recipe never shows StatBus/local, and no observed prompts are recorded (AC5, DoD).
---
<!-- COMMENTS:END -->
