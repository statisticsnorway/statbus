---
id: STATBUS-358
title: >-
  ACME DNS certificates for installed sites: acme-dns at cert.statbus.org, Caddy acme-dns module, CLI registers and instructs
status: To Do
assignee: []
created_date: '2026-09-07 07:02'
updated_date: '2026-09-23 15:10'
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
wildcard to give. The chosen design uses ACME DNS-01 through a StatBus-owned
Go certificate service hosted at `cert.statbus.org` (owner decision below):

1. The box calls `https://cert.statbus.org/register` once and receives a
   per-box credential (username, password, fulldomain, subdomain). That
   credential can only ever update its own `_acme-challenge` TXT record;
   nothing else in our DNS is reachable with it.
2. The NSO creates ONE DNS record: a CNAME from
   `_acme-challenge.<their-statbus-host>` to the `fulldomain` returned by
   `/register`. No subzone delegation, no wildcard.
3. Caddy on the box, using its acme-dns DNS provider module, answers the
   DNS-01 challenge through `cert.statbus.org` and renews on its own.
4. Registration is by ASK-AND-APPROVE, not by a shared secret and not by
   VPN reachability. See "Authorisation" below.

## Authorisation: why the VPN gate is not good enough (owner, 2026-09-07)

Stock acme-dns has an open `/register` with no security of its own; the
original plan made it safe by exposing it only on our VPN, which also let us
assist clients. Many NSOs refuse us any VPN access, including WireGuard,
Albania among them. So the fallback (`--cert-register-key`) becomes the
normal path, and it has the unsolvable problem of getting a secret into a
server we cannot reach: nothing to paste it with, no QR to scan.

The design that fits the constraint: **the box asks, we approve.**

- The box registers itself on first `./sb cert acme-dns register`, with no
  secret, and receives a stable identity plus a PENDING status.
- We see "Albania wants a certificate" on our side and approve it (a person,
  a CLI verb, or a small admin page). Until approved, the identity is useless:
  no TXT record can be written with it.
- After approval the box proceeds exactly as stock acme-dns: DNS-01 through
  `cert.statbus.org`, Caddy renews on its own.
- Nobody can abuse `/register` beyond creating a pending entry we ignore.

Consequences:

- **Identity must be durable.** Approval is of a specific registrant, so the
  box must present the SAME identity before and after approval, across
  restarts, recreates, and restores. That identity (acme-dns username,
  password, subdomain, fulldomain) is written to `.env.credentials` at first
  registration and never regenerated. A box that loses it is a new
  registrant and needs a new approval. This is the `.env.credentials`
  discipline exactly (stable identity across recreate/restore).
- **Stock acme-dns cannot do this alone.** It has no pending/approved state.
  Our Go service owns registration, approval, identities, and challenge records
  in our Postgres database on niue. Investigate only whether acme-dns is
  importable as a DNS-answering library, or whether that portion needs a fork.
- **`--cert-register-key` is dropped** from the design unless the
  investigation shows ask-and-approve cannot work; it is the thing we cannot
  deliver to an unreachable box.
- Operator experience on the box: `register` prints the identity and the
  CNAME to create, says "pending approval by SSB", and `./sb cert acme-dns
  check` reports pending / approved / CNAME missing / CNAME correct.

On the server we run our own Go certificate service; acme-dns is at most a library for DNS answering. This service is the one new component.

## Owner decision, 2026-09-24

> The certificate service is a Go service of ours, using our own Postgres database on niue for registrations, pending/approved state, per-box identities and the challenge records; hosted behind Caddy on niue at cert.statbus.org. acme-dns is at most a library for the DNS answering part.

This settles open point 3's approval-state location. The library-versus-fork question remains limited to DNS answering and still needs investigation. This is a design decision, not evidence that the service exists.

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

1. **Server:** build and deploy our Go certificate service behind Caddy on
   niue at `cert.statbus.org`, with registration, approval, per-box identity,
   and challenge records in our Postgres database. Register one test client
   and prove issuance with a hand-written Caddy config. Record the exact
   `/register` response and the CNAME the NSO must create in this ticket.
2. **Caddy image:** add `--with github.com/caddy-dns/acmedns` to
   `caddy/Dockerfile`; confirm the module lists in `caddy list-modules`.
3. **Investigation (before any CLI work):** can acme-dns be used as a Go
   library solely for DNS answering, or does that part need a fork? Approval
   and challenge state belong in our Postgres database on niue (owner decision
   2026-09-24). Define the approval verb on our side (`./cloud.sh cert approve
   <identity>` is the natural home after STATBUS-337) and record its contract
   here before implementation.
4. **CLI:** `./sb cert acme-dns register` registers once, stores the durable
   identity in `.env.credentials` (creation-header discipline, never
   regenerated, never auto-propagated), prints the one CNAME the operator
   must create with copy-paste values, and says the request is pending SSB
   approval. `./sb config generate` renders the Caddyfile `tls` block from
   that identity when present. `./sb cert acme-dns check` reports approval
   state and whether the CNAME resolves to the expected fulldomain, so
   failures surface at the operator's desk before Caddy tries to issue.
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
6. The library-vs-fork and approval-state investigation is written in this ticket, and a box that is recreated or restored keeps its identity and approval.

## Out of scope

Re-testing plain HTTP-challenge ACME on a public IP (proven daily on cloud
and Norway). HTTPS-only egress (STATBUS-357).
<!-- SECTION:DESCRIPTION:END -->

## Reconciliation 2026-09-23

Classification: OPEN. Evidence: design only; no acme-dns command, credential flow, Caddy module, or live proof exists. No part of the item's own done-when is complete beyond any design already recorded above.
