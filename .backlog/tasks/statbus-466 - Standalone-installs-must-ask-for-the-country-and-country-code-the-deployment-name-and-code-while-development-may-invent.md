---
id: STATBUS-466
title: >-
  Standalone installs must ask for the country and country code (the deployment
  name and code), while development may invent
status: In Progress
assignee: []
created_date: '2026-10-08 12:07'
updated_date: '2026-10-08 12:08'
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
- [ ] #1 In a standalone installation the prompts ask for the country name shown in the interface and the country code used in container names and the subdomain, with concrete examples, and the rendered prompts are observed to say so.
- [ ] #2 Pressing Enter through a standalone install never silently yields the development defaults StatBus and local; the standalone suggestion comes from a real signal such as the domain answer, or entry is required.
- [ ] #3 The country code is validated for shape, short and lowercase, and a value that does not look like a country code produces a warning while an explained path lets a deliberate test installation proceed.
- [ ] #4 Development keeps its permissive prompts and invented defaults.
- [ ] #5 Tests cover standalone country-shaped answers, development invented answers, and the press-Enter path for both, and the standalone case is verified through the interactive install path with the observed prompts recorded.
<!-- AC:END -->

## Definition of Done
<!-- DOD:BEGIN -->
- [ ] #1 The observed prompts for a standalone run and for a development run are recorded in the ticket, not only asserted in tests.
<!-- DOD:END -->
