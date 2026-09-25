---
id: STATBUS-418
title: The harness proofs of record install StatBus the way a national statistical office does
status: To Do
assignee: []
created_date: '2026-09-25 12:20'
updated_date: '2026-09-25 12:20'
labels:
  - harness
  - owner-decision
dependencies: []
priority: high
type: enhancement
ordinal: 368100
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
The release ladder's proofs of record (rung 4 `0-happy-install`, rung 5 `0-happy-upgrade`) and the fault fleet must exercise the deployment an NSO actually performs, so a green candidate means an NSO install works.

## What the project documents (read 2026-09-25)

- `doc/DEPLOYMENT.md:37-55`: **standalone** = "Single-server production deployment", "Use case: National statistical office deploying for one country"; requires a public domain name, DNS A record, open ports 80/443/5432; automatic ACME/Let's Encrypt, custom certificates supported (`doc/DEPLOYMENT.md:562+`).
- `doc/DEPLOYMENT.md:57-67`: **private** = "Behind host-level reverse proxy", HTTP only, "Use case: Part of multi-tenant cloud deployment" (niue; `doc/CLOUD.md:223,231,250` new country slots on niue use private).
- `doc/DEPLOYMENT.md:26-35`: **development** = local development, Next.js on the host.
- `doc/DEPLOYMENT.md:122-162`: NSO procedure = `ops/setup-ubuntu-lts.sh` (step 1), then as the `statbus` service account `curl -fsSL https://statbus.org/install.sh | bash` (interactive) or the unattended form with `CADDY_DEPLOYMENT_MODE`, `SITE_DOMAIN`, `DEPLOYMENT_SLOT_NAME`, `DEPLOYMENT_SLOT_CODE`, `TRUST_GITHUB_USER`.
- `doc/CLOUD.md:700-702`: SSB runs `rune.statbus.org` in standalone "exactly as external clients deploy from DEPLOYMENT.md" to dog-food that path.

## What the harness tests today

- `test/install-recovery/scenarios/0-happy-install.sh:24-31,84` requires **private** (comment calls private "an NSO mode", contradicting DEPLOYMENT.md); introduced `ce539f014` (2026-09-14); `doc/release-ladder.md:21` rung 4 states "NSO private mode".
- `test/install-recovery/scenarios/0-happy-upgrade.sh:57-65` uses **development** on purpose: standalone needs real ports 80/443 and public ACME, and a harness VM named `statbus-test.local` has no public DNS (STATBUS-339 review, 2026-09-06).
- `test/install-recovery/lib/vm-bootstrap.sh:711` defaults to development; only 4-install-port-80-taken, 5-install-orphaned-db-volume-credentials and 4-install-standalone-no-public-dns use standalone.

Consequence: the standalone path (Finland's, rune's) is the least-proven by the release gate.

## Open question for the owner (not decided)

Which mode(s) must rungs 4 and 5 and the fault-fleet base use, and how does a harness box obtain a certificate in standalone? Candidate approaches recorded in conversation, none chosen: real per-VM names under a test domain with ACME (staging endpoint), the private-certificate work (STATBUS-399/358), or standalone asserting graceful certificate behaviour. Ground each against Let's Encrypt limits and `doc/install-upgrade-testing.md` before deciding.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Owner decision recorded here: the mode(s) of rung 4, rung 5 and the STATBUS-417 fault-fleet base, and the certificate approach.
- [ ] #2 `0-happy-install.sh`, `0-happy-upgrade.sh`, `doc/release-ladder.md` and `vm-bootstrap.sh` defaults state and use the decided mode(s); comments match DEPLOYMENT.md.
- [ ] #3 A candidate gate run proves the decided NSO path green (run id recorded here).
<!-- AC:END -->
