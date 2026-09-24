---
id: STATBUS-357
title: >-
  https-only egress scenario: a box whose network blocks outbound HTTP must
  install and upgrade (the Albania shape)
status: To Do
assignee: []
created_date: '2026-09-07 07:02'
updated_date: '2026-09-23 15:10'
labels:
  - harness
  - install
  - upgrade
  - fidelity
dependencies:
  - STATBUS-363
references:
  - install.sh
  - test/install-recovery/lib/vm-bootstrap.sh
  - test/install-recovery/scenarios/0-happy-upgrade.sh
  - cli/internal/upgrade/github.go
  - cli/internal/upgrade/ghcr.go
priority: medium
type: task
ordinal: 50
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
## Why

Albania's network drops or rejects all outbound plain-HTTP traffic. To
install there, the owner had to make every outbound fetch HTTPS by hand. That
hack is not tested: nothing in the 15 fleet scenarios or 32 arcs runs on a
box that cannot speak HTTP outward, so a future change that reintroduces one
plain-HTTP fetch (an apt mirror, a redirect that lands on http://, a docker
pull through an http registry mirror, an ACME http-01 challenge) would pass
every test and fail in Albania.

## Ground truth (2026-09-07)

- Product code reaches out to `https://github.com`, `https://api.github.com`,
  and `https://ghcr.io` only (install.sh, cli/internal/upgrade/github.go,
  ghcr.go). The only `http://` literals in product code are loopback or
  docker-internal (`127.0.0.1`, `proxy:80`, `.local`).
- The owner's Albania hack is not yet located in code by this ticket; step 1
  is to find and record it (it may be an install.sh switch, an
  `.env.config` entry, or an ops note). Until it is written down here, the
  scenario cannot know what it is protecting.
- Harness VMs bootstrap through `test/install-recovery/lib/vm-bootstrap.sh`,
  which is where an egress rule would be applied.

## Work

1. **Locate the hack.** Read install.sh, ops/, doc/, and the Albania box's
   notes; write in this ticket exactly which fetches were plain HTTP before and
   what forces them to HTTPS now. If it is only operator discipline (nothing in
   code), say so; the scenario then guards the current all-HTTPS state.
2. **One new fleet scenario** `X-https-only-egress` (name per the phase
   convention of its siblings): after VM bootstrap and before install, apply
   an egress rule that REJECTS outbound TCP port 80 (`iptables -A OUTPUT -p
   tcp --dport 80 -j REJECT`, made persistent for the VM's life). Then run
   the ordinary install at the dynamic baseline and the ordinary upgrade to
   the tagged candidate, exactly like `0-happy-upgrade`. Any plain-HTTP fetch
   fails fast and the scenario goes red naming it.
3. Prefer REJECT over DROP so failures are immediate, not 2-minute timeouts;
   note in the header that Albania's real network may DROP, and that REJECT
   is the stricter, faster proxy for it.
4. The scenario must be in `--print-selected` (default suite) so the
   orchestrator runs it on every candidate that touches install/upgrade
   payload.

## Acceptance

1. The hack is documented in this ticket with file and line references, or
   its absence is stated.
2. The scenario is listed, selected, and green on a real RC tag in the
   install-recovery harness (rides the next paid run after it lands; do not
   cut an RC for it alone).
3. A deliberate plain-HTTP fetch injected into a scratch copy of install.sh
   makes the scenario red with a message naming the URL (proves the guard
   bites).

## Out of scope

Certificates and TLS for the box's OWN listeners (that is STATBUS-358).
Standalone deployment mode on a harness VM (needs a harness-safe
certificate first; also STATBUS-358).
<!-- SECTION:DESCRIPTION:END -->

## Batch sequencing (owner ruling 2026-09-15)

This ticket lands in the ONE batch after the current release: it does not
touch master until v2026.09.1-rc.08 (or the first later rc that goes fully
green) has been installed on Norway and promoted to stable. Then all batch
tickets land in one push, one candidate, one ladder. Position in that push:
**5 of 8**. https-only egress scenario; being built by palmtree (Astra) in scratch; joins --print-selected so the batch ladder runs it

Batch order: 370 -> 368 -> 367 -> 363 -> 357 -> 361 -> 362 -> 359.

## Reconciliation 2026-09-23

Classification: PARTIAL. Evidence: scratch design/build is recorded, but nothing landed and no paid RC proof exists.

Remaining: Land the HTTPS-only egress scenario, its mutation control, and obtain a green paid RC run.

## 2026-09-24 status

HTTPS-only egress runs on demand since `fe4a769a7`. Branch
`next/357-egress-default` at `61ece22d1` matches the pre-NAT destination and
returns it to the default set; it is under review. Next step: merge after
review and obtain the real proof in the next candidate harness run.

## Implementation 2026-09-23

No Albania-specific product switch or checked-in operator hack exists. The
current install and upgrade paths use HTTPS for external GitHub and GHCR reads;
plain-HTTP product literals are loopback or container-internal. The new
`0-https-only-egress` scenario therefore guards that current all-HTTPS state.

The scenario reuses `0-happy-upgrade.sh` and, immediately after VM bootstrap,
adds `iptables -A OUTPUT -p tcp --dport 80 -j REJECT`. Its deliberate mutation
fetches `http://example.com/statbus-http-egress-mutation`, requires rejection,
and prints that URL in the passing diagnostic. The scenario is discovered by
the default dispatcher. A real install and upgrade can only be proven by the
next paid candidate harness run, so status remains **To Do** pending that run.

## Fix-forward 2026-09-23

The egress guard now installs matching `iptables` and `ip6tables` OUTPUT rules,
then attempts the deliberate HTTP mutation with both `curl -4` and `curl -6`.
The local regression asserts both firewall families and both address-family
probes. The real harness scenario executes these commands on its Ubuntu VM.

## Firewall-tool fix-forward 2026-09-23

The scenario now owns its firewall prerequisite instead of relying on `ufw` or
another hardening dependency to provide it indirectly. It checks for both
`iptables` and `ip6tables`, installs Ubuntu's `iptables` package when either is
absent, re-checks both commands, and invokes both `--version` paths before
installing rules. Ubuntu's package normally exposes nftables-backed alternatives,
so retaining the two existing commands is simpler than adding separate `nft`
rule syntax while still exercising both address families explicitly.

After installing both rules, the scenario probes TCP/80 at IPv4 and IPv6
literals with short timeouts and requires curl's connection-failure status. It
first checks for an IPv6 route; an image without one emits an explicit
`VACUOUS` diagnostic rather than silently counting unrelated lack of IPv6 as
firewall proof. The offline contract pins ensure-tools → install-rules →
verify-both-families ordering and includes a scratch mutation that removes the
`ip6tables` rule. Actual Ubuntu 24.04 and 26.04 behavior remains pending the
first paid VM run, which is the real proof for those images.

## Hardened-firewall correction 2026-09-23

The preceding package choice was incorrect for this scenario: it created a
parallel iptables firewall instead of exercising the box produced by
`ops/setup-ubuntu-lts.sh`. Security stage 4 installs
`crowdsec-firewall-bouncer-nftables` and configures UFW, so this scenario now
enables that normally skipped harness stage and requires its `nft` command to
be usable. It installs no firewall package itself.

After hardening, the scenario creates one dedicated `inet`-family nftables
output chain and one `tcp dport 80 reject` rule. The inet family covers IPv4
and IPv6 with the same rule. The literal-address probes and explicit no-IPv6-
route `VACUOUS` diagnostic remain. Because the scenario delegates to
`0-happy-upgrade.sh`, its actual VM image is the explicit Ubuntu 24.04 pin in
that file, not the harness's Ubuntu 26.04 default. The offline mutation now
removes the single inet rule and must turn the contract red.

## OS decision correction 2026-09-23

Owner decision: HTTPS-only egress tests the principle on the Ubuntu 26.04
harness default and adds no older-LTS run. `0-happy-upgrade` remains the sole
Ubuntu 24.04 scenario. Its shared flow now applies the 24.04 pin only for its
own entry point; when `0-https-only-egress` delegates with its marker set, no
image override is applied and `vm-bootstrap.sh` resolves Ubuntu 26.04. The
image-selection offline contract asserts both sides of this split.

## On-demand correction 2026-09-24

The three paid-run findings are now explicit. First, the hardened operator is
restricted and cannot install the root-owned nftables rule itself. Second, the
harness health assertion uses the loopback address `127.0.0.1:3010`. Third,
that address is a Docker-published port: Docker 29 DNATs locally originated
traffic in `nat OUTPUT` before the filter output hook, so the rule sees bridge
traffic to the proxy container on port 80 and a loopback-interface exemption
cannot match. The rc.03 evidence also showed that no product code path used
external TCP/80.

For this release, `0-https-only-egress` is therefore marked
`HARNESS_SKIP_DEFAULT`. Its rule and assertions are unchanged, and it remains
runnable by name, but it no longer gates the default paid fleet.

Next cycle, exempt the Docker-published loopback path correctly, for example by
matching the original destination with `ct original daddr 127.0.0.0/8`, or by
placing the reject in a hook/priority after conntrack NAT with the corresponding
original-destination match. Prove the correction on a real VM, then remove the
skip marker and re-enable default selection.

## Docker userland-proxy destination correction 2026-09-24

The corrected policy allows loopback and private-destination HTTP while refusing
public-destination TCP/80. With Docker's default `userland-proxy=true`, Docker's
nat `OUTPUT` jump excludes loopback. A request to `127.0.0.1:3010` is therefore
not DNATed. `docker-proxy` accepts that host connection and opens a second,
brand-new connection from the host to the container IP, for example
`172.18.0.3:80`. The filter `OUTPUT` hook sees that container destination, and
its conntrack original destination is also the container IP because no NAT is
involved.

The dedicated `inet` table consequently exempts destination scopes rather than
host-assigned addresses. IPv4 loopback and RFC1918 ranges, including Docker's
default `172.16.0.0/12` bridge space, are allowed. IPv6 loopback, ULA, and
link-local ranges are allowed. Public IPv4 and IPv6 destination port 80 is
refused. Container-to-container traffic traverses the forward path and remains
unaffected.

The offline contract models the published-loopback request as the non-NATed
host -> `172.18.0.3:80` connection and decides rejection from membership in the
rule's exempt destination set. Its required mutation removes
`172.16.0.0/12`, which makes the docker-proxy health path red. The scenario
retains `HARNESS_SKIP_DEFAULT` and remains explicitly runnable on demand until
the corrected rule passes a paid real-VM run. The shared install flow also makes
a bounded at-install health request so a wrong rule fails in seconds.

This is an offline semantic and mutation proof. The acceptance-aligned proof is
still the next candidate's paid install-recovery harness run on a real VM. Do
not mark the ticket complete or remove the skip marker until that run is green.
