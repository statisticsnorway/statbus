# Host firewall (CrowdSec) on niue.statbus.org

`niue.statbus.org` runs CrowdSec with the nftables firewall bouncer
(installed by `ops/setup-ubuntu-lts-24.sh` Stage 4). When a scenario
fires (typically `crowdsecurity/ssh-bf` for SSH brute-force), the
bouncer drops all traffic from the offending source IP for 4 hours
by default. Drops are silent (no RST, no ICMP unreachable) — clients
see TCP timeouts that look like a host-level outage.

## Operator IPs are whitelisted

`/etc/crowdsec/parsers/s02-enrich/operator-whitelist.yaml` (a file
local to this host, NOT managed by the CrowdSec hub) contains the
operator workstation IP allowlist:

```yaml
name: ssb/operator-whitelist
description: "Whitelist SSB operator workstation IPs from triggering bans"
whitelist:
  reason: "SSB operator workstations — see doc/host-firewall.md for policy"
  ip:
    - "51.175.176.229"  # jorgen@veridit.no, NO Lyse Tele home/office, added 2026-04-22
```

A whitelisted IP can still hit `Failed password` / `Invalid user` log
lines, but the parser scrubs those events before they reach the
ssh-bf bucket — so the bucket never overflows from operator traffic
alone.

Whitelisting via parser file (rather than `cscli decisions add ...
--type whitelist`) is intentional:

- Persists across CrowdSec restart and upgrade.
- Visible in source control if we ever check the file in.
- Inspectable via `cscli parsers inspect ssb/operator-whitelist`.

## Adding a new operator IP

```bash
# As root on niue:
sudo vi /etc/crowdsec/parsers/s02-enrich/operator-whitelist.yaml
# Append a new ip: entry under whitelist:
sudo systemctl restart crowdsec
sudo cscli parsers inspect ssb/operator-whitelist | head -10  # confirm tainted: false
```

If the operator's IP was already banned at the time of editing,
unban it explicitly — the whitelist only stops new events, not
existing decisions:

```bash
sudo cscli decisions delete --ip <new-operator-ip>
```

## Diagnosing "host appears down"

When `curl https://<slot>.statbus.org/` or `ssh ...@niue.statbus.org`
times out without any TCP RST, suspect a CrowdSec ban:

1. **From a different network** (mobile hotspot, VPN to elsewhere,
   another host like `rune.statbus.org`), confirm niue itself is up.
   If niue is reachable from elsewhere, the issue is firewall-side.
2. **As root on niue** (use rune as a jump host:
   `ssh -J statbus@rune.statbus.org root@niue.statbus.org`):

   ```bash
   cscli decisions list                      # Shows current bans
   cscli alerts inspect <alert-id> --details # Shows what scored — target_user, log lines
   journalctl --since "1 hour ago" -u ssh \
       | grep -E "Failed|Invalid|preauth"    # Raw SSH evidence
   ```

3. **Unban yourself**:
   ```bash
   sudo cscli decisions delete --ip <your-ip>
   ```

4. **If the ban was triggered by your own legitimate tooling**
   (e.g. a cron probing a retired account): fix the tooling, then
   add the IP to the whitelist (above) so the next iteration of the
   problem doesn't re-ban you.

## Known root causes from past incidents

| Date       | Triggering source                                              | Fix                                                                                                          |
|------------|----------------------------------------------------------------|--------------------------------------------------------------------------------------------------------------|
| 2026-04-21 | Local script repeatedly SSHing to retired `statbus_no@niue` after slot retirement (commit `8fbbcd482`); 8 failed-auths in 24 s — over the ssh-bf threshold | Operator IP added to `operator-whitelist.yaml`. Triggering script identified as outside this repo (assumed a sibling agent's local cron / CI). |

When adding a new row, name the script and link the commit that
removed the targeted account, so the next operator can grep history
to find what to delete.

## Why we do NOT whitelist sibling-agent CI runner IPs

CI runner source IPs rotate (GitHub Actions Azure pool, Scaleway
runners, etc.). Allowlisting any one of them invites a stale entry
that grants access long after that runner is decommissioned.
Instead, fix the CI workflow that's hammering SSH to use a key
that succeeds first try (or a pre-shared host key + ProxyCommand
that doesn't trigger sshd auth retries).

## Permanent decisions vs whitelist

A permanent allowlist via the parser file (this doc) is the
correct mechanism for IPs we trust. CrowdSec also supports manual
decisions — `cscli decisions add --ip <ip> --type ban --duration 100y`
for permanent bans, `--type captcha` for captcha challenges. We do
not currently use either; the parser-whitelist + automatic ssh-bf
bans cover all observed cases.
