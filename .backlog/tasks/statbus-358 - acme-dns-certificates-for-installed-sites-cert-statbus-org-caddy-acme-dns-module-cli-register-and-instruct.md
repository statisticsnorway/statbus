---
id: STATBUS-358
title: A private-address site receives and renews a trusted certificate after one DNS change
status: To Do
assignee: []
created_date: '2026-09-07 07:02'
updated_date: '2026-09-25 13:53'
labels:
  - owner-decision
  - install
  - tls
  - design
dependencies: []
priority: medium
type: task
ordinal: 351000
---

## Status 2026-09-24

**To Do, owner decision:** #1-6 not met: certservice approval tests, delegated-DNS VM scenario, CNAME check, and provider spike are absent (`2d8f2668f` only records the ownership question). **Remaining:** agree who runs the service and provider strategy, then implement identity approval, trusted issuance, renewal, restore, and operator checks.

Baseline: `origin/master` at `373d15fc3`. Criterion disposition and remaining positive targets are above; the acceptance criteria below remain authoritative. An authored but unrun VM scenario is **proof pending**, not met.

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
A private-address installation registers a durable certificate identity, receives human Statistics Norway approval, creates the printed DNS CNAME, and then receives and renews a publicly trusted certificate. Recreate and restore preserve the same identity and approval. If the DNS-answering investigation selects an acme-dns library or provider module, its exact syntax is implemented only after that compatibility is proven.

## Owner decision, 2026-09-24

The approved architecture places registration, pending and approved state, per-box identities, and challenge records in a StatBus Go service backed by the StatBus PostgreSQL database on niue and served as `cert.statbus.org`. The remaining library-versus-fork and Caddy provider details are conditional research, not implemented facts. This is the primary owner-decision record for the operative target.

## Evidence, 2026-09-24

Current standalone configuration has automatic-ACME and supplied-certificate branches (`caddy/templates/standalone.caddyfile.tmpl:145-155` at master `7a9cf707e`). The current Caddy image builds only its existing modules (`caddy/Dockerfile:6` at master `7a9cf707e`), and current certificate CLI behavior begins at `cli/cmd/cert.go:46-89` at master `7a9cf707e`. No delegated DNS certificate service, registration command, approval flow, or renewal proof exists in master. The exact DNS-answering library, fork, and provider syntax remain conditional until a spike proves them.
## Owner decisions, 2026-09-25 13:43Z

- Built **concurrently** with STATBUS-399, not after it.
- The service lives in **its own repository** and **installs separately** (on SSB infrastructure, niue). The box-side registration/approval/renewal commands stay in this repo (cli/cmd/cert.go territory).

## Owner decisions, 2026-09-25 13:52Z — identity and approval

- Approval happens on the SSB side (sensible: a human approves each box).
- **Stable identifier, mandatory:** the identity we see and approve must be identical to the identity the box presents on every rerun. Persisted across reruns, recreate and restore (AC #4 already requires this).
- Box-side flow (with 399): installer stops and offers the choice interactively; non-interactive runs receive printed env vars and exactly what to report to SSB. No blocking wait inside the installer.

<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 `new: cli/internal/certservice/registration_approval_test.go::TestPendingIdentityRequiresHumanApproval` registers one identity, observes pending state, records human approval, and proves only that identity can update its challenge record.
- [ ] #2 `new: test/install-recovery/scenarios/4-install-delegated-dns-certificate.sh` registers once, preserves the identity, prints the exact CNAME, observes approval, creates the CNAME, and receives a trusted certificate.
- [ ] #3 `new: test/install-recovery/scenarios/4-install-delegated-dns-certificate.sh` advances the renewal window and observes automatic renewal with the same identity and no new approval.
- [ ] #4 `new: test/install-recovery/scenarios/4-install-delegated-dns-certificate.sh` recreates the application and restores from backup, then observes the same identity, approval, CNAME target, and renewed certificate.
- [ ] #5 `new: cli/cmd/cert_acme_dns_test.go::TestCheckReportsPendingApprovedMissingAndCorrectCNAME` covers all four operator-visible states with copy-paste values.
- [ ] #6 `new: cli/internal/config/caddy_dns_provider_test.go::TestDelegatedDNSBranchIsConditionalOnProvenProvider` names and tests the selected module and syntax only after `new: doc/certificate-dns-answering-spike.md` records the library-versus-fork result.
<!-- AC:END -->
