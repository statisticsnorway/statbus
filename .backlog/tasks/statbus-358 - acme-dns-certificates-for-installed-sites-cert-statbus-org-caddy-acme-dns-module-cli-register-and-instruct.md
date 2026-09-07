---
id: STATBUS-358
title: >-
  ACME DNS certificates for installed sites: acme-dns at cert.statbus.org, Caddy acme-dns module, CLI registers and instructs
status: To Do
assignee: []
created_date: '2026-09-07 07:02'
updated_date: '2026-09-07 07:08'
labels:
  - install
  - tls
  - design
  - harness
dependencies: []
references:
  - caddy/templates/standalone.caddyfile.tmpl
  - caddy/Dockerfile
  - cli/internal/config/config.go
  - cli/cmd/cert.go
  - doc/DEPLOYMENT.md
  - test/install-recovery/lib/vm-bootstrap.sh
priority: medium
type: task
ordinal: 351000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
## Owner's notes (verbatim, 2026-09-07)

* ACME DNS for our installed sites
* Complete setup of acme-dns after DNS changes and test with Caddy setup.
* Improve statbus CLI to instruct the users on how to setup
  acme-dns for cert.statbus.org in generated Caddyfile.
  Put the token in `.env.credentials` after getting it from /register
  and allow a command line --cert-register-key for access when there is no
  VPN with granted access.
* ACME DNS cert issuance from cert.statbus.org

## Why

Every StatBus box needs a certificate for its own HTTPS listener. Today:

| Way | Who | Tested where |
|---|---|---|
| Caddy obtains a Let's Encrypt cert automatically (HTTP challenge; needs a public IP and DNS) | our cloud slots, rune | every cloud deployment, Norway |
| NSO supplies its own certificate, usually a wildcard, via `./sb cert install` or `TLS_CERT_FILE`/`TLS_KEY_FILE` | some NSOs | `cli/cmd/cert.go` unit tests; no harness scenario |
| No certificate (development mode) | dev, the harness | every harness VM |
| **A private-IP NSO box gets a real certificate through DNS validation via our DNS** | most NSOs, in practice | **does not exist** |

The fourth case is the common one: the box is on a private IP behind the
NSO's firewall, the HTTP challenge cannot reach it, and the NSO may have no
wildcard to give. The chosen design is the standard ACME DNS-01 pattern with
an off-the-shelf **acme-dns** server we run at `cert.statbus.org`:

1. The box calls `https://cert.statbus.org/register` once and receives a
   per-box credential (username, password, fulldomain, subdomain). That
   credential can only ever update its own `_acme-challenge` TXT record;
   nothing else in our DNS is reachable with it.
2. The NSO creates ONE DNS record: a CNAME from
   `_acme-challenge.<their-statbus-host>` to the `fulldomain` returned by
   `/register`. No subzone delegation, no wildcard.
3. Caddy on the box, using its acme-dns DNS provider module, answers the
   DNS-01 challenge through `cert.statbus.org` and renews on its own.
4. Registration is reachable from the VPN with granted access. For an
   operator without that, `--cert-register-key` presents a key that
   `/register` accepts; see the open point below.

There is nothing to build on the server beyond running acme-dns.

## Ground truth (2026-09-07)

- No acme-dns, `cert.statbus.org`, or DNS-01 code exists in the repository
  yet (grep: zero hits).
- `caddy/Dockerfile` builds Caddy with `xcaddy build --with
  github.com/mholt/caddy-l4` only; the acme-dns DNS provider module
  (`github.com/caddy-dns/acmedns`) must be added to that build.
- `caddy/templates/standalone.caddyfile.tmpl` renders either `tls
  <cert> <key>` (custom) or `tls { issuer acme }` (HTTP challenge). A third
  branch is needed: `tls { dns acmedns { ... } }` fed from the registered
  credential.
- `.env.credentials` is written once by `./sb config generate` with a header
  saying a running system never reads it back (config.go ~269). The acme-dns
  credential belongs there: stable identity that a recreate or restore must
  get back. Rendering it into the Caddyfile is the ordinary generate path.
- `./sb cert` today has `show` and `install`; a registration verb is the
  natural addition.

## Work, in order

1. **Server:** finish the acme-dns setup at `cert.statbus.org` after the DNS
   changes; register one test client by hand and prove issuance with a
   hand-written Caddy config. Record the exact `/register` response shape
   and the CNAME the NSO must create in this ticket.
2. **Caddy image:** add `--with github.com/caddy-dns/acmedns` to
   `caddy/Dockerfile`; confirm the module lists in `caddy list-modules`.
3. **CLI:** `./sb cert acme-dns register [--cert-register-key K]` calls
   `/register`, stores the credential in `.env.credentials` (creation-header
   discipline, never auto-propagated), and prints the one CNAME the
   operator must create with copy-paste values. `./sb config generate`
   renders the Caddyfile `tls` block from that credential when present. A
   `./sb cert acme-dns check` verifies the CNAME resolves to the expected
   fulldomain before the first issuance attempt, so the failure is at the
   operator's desk, not in Caddy's log.
4. **Open point to rule before step 3 ships:** what `--cert-register-key`
   is. Options: a static shared secret in our ops vault (simple, revocable
   by rotation, leak means anyone can register a subdomain until rotated);
   or per-NSO keys we issue. Either is fine for a first release since a
   leaked key only lets someone obtain a `_acme-challenge` subdomain under
   `cert.statbus.org`, not a certificate for any name they do not control.
   Write the choice here.
5. **Fallback stated in docs:** if `cert.statbus.org` is unreachable at
   renewal, Caddy keeps serving the existing certificate and logs the
   failure; the box never drops to plain HTTP. `./sb cert show` should say
   when the cert is within N days of expiry so an operator notices.
6. **Harness scenario A:** a VM with NO public DNS record for its own name
   registers with acme-dns, the harness creates the CNAME in a zone it
   controls, Caddy issues via DNS-01, and the scenario asserts the served
   chain validates. This is the scenario that also lets standalone mode run
   on harness VMs (STATBUS-339 review finding).
7. **Harness scenario B:** the customer-supplied path, `./sb cert install`
   with a self-signed wildcard generated on the VM, served and validated
   against that self-signed CA. No end-to-end test of that path exists.

## Acceptance

1. A private-IP box (harness scenario A) serves a valid Let's Encrypt
   certificate obtained through `cert.statbus.org` with one operator action
   (the CNAME) and one CLI command.
2. The credential lives in `.env.credentials`; recreate and restore keep it.
3. `./sb cert acme-dns check` catches a missing or wrong CNAME before
   issuance.
4. The Caddy image carries the acme-dns module; the template renders the
   third branch only when the credential is present.
5. Scenario B is green and the `cert install` path is proven end to end.
6. The register-key decision is written in this ticket.

## Out of scope

Re-testing plain HTTP-challenge ACME on a public IP (proven daily on cloud
and Norway). HTTPS-only egress (STATBUS-357).
<!-- SECTION:DESCRIPTION:END -->
