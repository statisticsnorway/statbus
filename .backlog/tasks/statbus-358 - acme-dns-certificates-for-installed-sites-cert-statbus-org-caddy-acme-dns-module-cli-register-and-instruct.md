---
id: STATBUS-358
title: A private-address site receives and renews a trusted certificate after one DNS change
status: To Do
assignee: []
created_date: '2026-09-07 07:02'
updated_date: '2026-09-24 18:47'
labels:
  - install
  - tls
  - design
  - harness
dependencies: []
priority: medium
type: task
ordinal: 351000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
A private-address installation registers a durable certificate identity, receives human Statistics Norway approval, creates the printed DNS CNAME, and then receives and renews a publicly trusted certificate. Recreate and restore preserve the same identity and approval. If the DNS-answering investigation selects an acme-dns library or provider module, its exact syntax is implemented only after that compatibility is proven.

## Owner decision, 2026-09-24

The approved architecture places registration, pending and approved state, per-box identities, and challenge records in a StatBus Go service backed by the StatBus PostgreSQL database on niue and served as `cert.statbus.org`. The remaining library-versus-fork and Caddy provider details are conditional research, not implemented facts. This is the primary owner-decision record for the operative target.

## Evidence, 2026-09-24

Current standalone configuration has automatic-ACME and supplied-certificate branches (`caddy/templates/standalone.caddyfile.tmpl:145-155` at master `7a9cf707e`). The current Caddy image builds only its existing modules (`caddy/Dockerfile:6` at master `7a9cf707e`), and current certificate CLI behavior begins at `cli/cmd/cert.go:46-89` at master `7a9cf707e`. No delegated DNS certificate service, registration command, approval flow, or renewal proof exists in master. The exact DNS-answering library, fork, and provider syntax remain conditional until a spike proves them.
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
