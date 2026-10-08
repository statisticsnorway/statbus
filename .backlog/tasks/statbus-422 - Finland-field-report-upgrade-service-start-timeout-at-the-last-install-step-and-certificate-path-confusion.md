---
id: STATBUS-422
title: >-
  Finland field report: upgrade-service start timeout at the last install step,
  and certificate path confusion
status: In Progress
assignee: []
created_date: '2026-09-27 10:07'
updated_date: '2026-10-08 10:17'
labels:
  - installer
dependencies: []
priority: high
ordinal: 371200
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Ville-Mattis Pilvio, 2026-09-25 (v2026.09.2 era). Owner asked to capture for discussion on his return.
## The report (Ville, 2026-09-25, v2026.09.2-era binary)

Fresh install on statbus.statfin.eu. Steps 1-16 all green; step 17 failed:

```
[17/17] Upgrade service      RUNNING
  Unit statbus-upgrade@statbus.service is in failed state — running reset-failed
  Enabling and starting statbus-upgrade@statbus.service
Job ... failed because a timeout was exceeded.
[17/17] Upgrade service      FAILED: enable service: exit status 1
INVARIANT FAILED_INSTALL_HAS_AUDIT_TRAIL violated (audit-only): install failed with no upgrade row (detectedState=db-unreachable) ...
```

Ville's own guess: "I needed to remove a service beforehand" (a leftover failed unit from a previous attempt).

## Defects/questions this exposes (for owner discussion)

1. **Step 17 robustness:** a previously failed unit gets reset-failed but the start still timed out. The installer needs the unit's actual journal in the failure output (the log says "See systemctl status" — the operator gets no cause), and the start must tolerate/clean a wedged prior unit. What timed out — the service's first-boot work (config generate, recovery scan) exceeding TimeoutStartSec?
2. **detectedState=db-unreachable is wrong-looking:** the DB was healthy at step 8 (services all healthy) yet the audit invariant classified db-unreachable. Audit-only, but the classification deserves a look.
3. **Certificate path confusion:** his .env.config has `TLS_CERT_FILE=/home/statbus/statbus.crt` — HOST paths. The documented values are CONTAINER paths (/data/custom-certs/...). The installer/config should validate that the cert files exist at the container path and print the mapping expectation, instead of failing later and mysteriously.
4. **Legacy placeholder placement:** his .env.config carries SEQ_API_KEY/SLACK_TOKEN placeholder values — exactly what STATBUS-361 migrates. His box is the migration's target case; the rc.07-era crash-loop fix (service-side migration) covers the upgrade path.
5. He had to hand-add SITE_DOMAIN to .env.config — worth checking whether the flow told him to (the FRESH refusal leaves the documented file to edit — did the guidance reach him?).

## Triage (coordinator, 2026-09-27 10:10Z; owner: "build the clear ones now")

Moving to implementation now: (1) step-17 failure must include the upgrade unit's journal tail so the operator sees the cause, and (2) TLS_CERT_FILE/TLS_KEY_FILE validation must catch host-path-vs-container-path confusion with a clear message. Waiting for owner discussion: the certificate UX flow (belongs to 399), whether the wedged-unit cleanup needs a design decision, and the db-unreachable audit classification.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 The cause of the 24/25 Sep step-17 start timeout is reproduced on v2026.09.2 (LXD replay) and shown fixed or refused with a named cause on v2026.09.3
- [ ] #2 The installer tells a standalone operator to set SITE_DOMAIN (or asks for it) before a certificate can be issued; Ville's hand-edit is not needed
- [ ] #3 A short, confirmed instruction is sent to Ville for the stable v2026.09.3 install with his custom certificate
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
NEW FIELD REPORT FROM FINLAND, 2026-10-08 (Ville-Mattis Pilvio, fresh install of the bce5bf39 images, the v2026.10.0/rc.20 commit). Different symptoms from the 2026-09-25 report: uninstall and install now run without issues, but the box is not usable. Evidence: http://local.statbus.org/ does not work; http://127.0.0.1:3012/login fails with 'Login failed: UNKNOWN_FAILURE'; the footer shows 'Statbus version unknown (bce5bf39)'; Erik asks 'cannot connect to database??'. Ville's docker compose ps, as pasted, lists only statbus-local-app (3012), statbus-local-db (healthy) and statbus-local-proxy (3010/3011/3014/3015) and does NOT list rest or worker. DIAGNOSTIC INSIGHT (coordinator, from the compose profiles): app requires profile 'all' or 'app'; db, proxy, rest and worker all require 'all' or 'all_except_app'. A listing that contains db, proxy AND app is therefore only consistent with profile 'all', which also starts rest and worker. So their absence means one of: (a) the pasted output is incomplete, (b) rest and/or worker exited and docker compose ps hides stopped containers by default, or (c) an unusual start. The most likely cause of the login failure is that PostgREST (rest) is not running or not reachable, because the app authenticates through /rest/rpc/login; its absence produces exactly 'UNKNOWN_FAILURE' plus 'cannot connect to database'. ASKED FOR FROM THE FIELD (not yet received): ./sb ps or docker compose ps --all, to include stopped containers; ./sb logs rest, ./sb logs proxy, ./sb logs app tails; curl -sS -o /dev/null -w '%{http_code}' http://127.0.0.1:3013/ (PostgREST direct) and http://127.0.0.1:3012/login; ./sb config show to confirm mode, slot and ports; and whether the stack was started with ./sb start all. SEPARATE DISPLAY DEFECT worth its own ticket: the footer reads 'Statbus version unknown (bce5bf39)'. The commit SHA is known, so the version string should be informative; the version metadata is not resolvable on that install.
<!-- SECTION:NOTES:END -->
