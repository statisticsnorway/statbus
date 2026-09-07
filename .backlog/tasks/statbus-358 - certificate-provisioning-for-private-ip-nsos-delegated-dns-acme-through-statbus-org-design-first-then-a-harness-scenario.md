---
id: STATBUS-358
title: >-
  certificate provisioning for private-IP NSOs: delegated-DNS ACME through statbus.org, design first, then a harness scenario
status: To Do
assignee: []
created_date: '2026-09-07 07:02'
updated_date: '2026-09-07 07:02'
labels:
  - install
  - tls
  - design
  - harness
dependencies: []
references:
  - caddy/templates/standalone.caddyfile.tmpl
  - cli/cmd/cert.go
  - doc/DEPLOYMENT.md
  - test/install-recovery/lib/vm-bootstrap.sh
priority: medium
type: task
ordinal: 351000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
## Why

Every StatBus box needs a certificate for its own HTTPS listener. Today there
are three ways, and a fourth is missing:

| Way | Who | Tested where |
|---|---|---|
| Caddy obtains a Let's Encrypt cert automatically (ACME, needs a public IP and DNS) | our cloud slots, rune | every cloud deployment, Norway |
| NSO supplies its own certificate, usually a wildcard, via `./sb cert install` or `TLS_CERT_FILE`/`TLS_KEY_FILE` | most NSOs | `cli/cmd/cert.go` unit tests; no harness scenario |
| No certificate (development mode) | dev, the harness | every harness VM |
| **A private-IP NSO box that cannot be reached by ACME gets a real certificate through us** | most NSOs, in practice | **does not exist** |

The fourth case is the common one. An NSO installs on a private IP behind its
firewall. ACME cannot reach it, and the NSO may not have a wildcard to give.
What we CAN do is let the NSO delegate a DNS zone (e.g. `al.statbus.org` or a
name under their own domain that CNAMEs to us) to our DNS, and have the box
obtain a certificate for its private-IP hostname via the DNS-01 challenge
through our DNS provider, with the authorisation coming from us.

## Design questions (rule before build)

1. **How does the box get authorised?** Options: (a) a code the operator
   types at install; (b) the box registers during install, we see "Albania
   wants in" and approve it on our side, and the box polls for approval; (c)
   a pre-shared key delivered out of band. (b) is the owner's leaning: no
   weird key to type, and nobody can abuse it without our approval.
2. **What does delegation look like for the NSO?** A CNAME of
   `_acme-challenge.<their-host>` to a name we control is the least
   invasive; delegating a whole subzone is more. Write both down with the DNS
   records the NSO must create.
3. **What runs on our side?** A small approval service plus DNS-01 solver
   credentials for our zone; Caddy on the box uses the DNS-01 issuer with a
   token scoped to that one name. Never our provider's master credential on
   an NSO box.
4. **Renewal and revocation.** Boxes renew through the same path; we can
   revoke by removing the record or the approval.
5. **Fallback.** If our service is unreachable the box must keep serving with
   its current certificate and say so, never drop to plain HTTP.

## Work, in order

1. Write the design as `doc/certificate-provisioning.md` answering the five
   questions above; present it for a ruling. The owner has existing notes for
   this; find and fold them in before writing.
2. Only after the ruling: implement the box side (`./sb cert request` or an
   install.sh flag), the approval side, and the Caddy template branch.
3. One harness scenario: a VM with NO public DNS record obtains a certificate
   through the delegated path and serves HTTPS on it; the scenario asserts
   the chain validates against the issuer. This also unblocks running
   standalone mode on harness VMs (STATBUS-339 review finding), which today
   cannot get a certificate at all.
4. A harness scenario for the customer-supplied-certificate path
   (`./sb cert install` with a self-signed wildcard generated on the VM),
   since that path has no end-to-end test today.

## Out of scope

Re-testing plain ACME on a public IP (proven daily on cloud and Norway).
HTTPS-only egress (STATBUS-357).
<!-- SECTION:DESCRIPTION:END -->
