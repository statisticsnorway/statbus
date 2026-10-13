# STATBUS-357 / STATBUS-485: HTTPS-only egress, real LXD run 1

Verdict: **PASS** (`comparison.tsv`: `0-https-only-egress  PASS  119s  rc=0  installed-v2026.09.3-standalone`, `fleet-status.txt`: `STATUS=PASSED`).

## Run identity

| Field | Value |
| --- | --- |
| Candidate tag | `v2026.10.0-rc.20` (`bce5bf39b73fcb87ee55900fab927c36872e23c0`) |
| Upgrade path | v2026.09.3 (baseline checkpoint, real installer) → v2026.10.0-rc.20 |
| Run kind | Operator-run on-demand LXD fork. **No GitHub Actions run URL exists for this run**; it was driven from a workstation exactly as `lxd-fleet.yaml`'s driver step does (marker acquire, then `run-forks.sh`). |
| Command | `test/install-recovery/lxd/run-forks.sh v2026.10.0-rc.20 --scenario 0-https-only-egress` |
| Harness commit | `55731c7cb` (LXD backend incl. the delegation fix below) |
| Fleet host | `statbus-lxd-fleet` (Hetzner ccx33, hel1, `ubuntu-26.04` image), ramped by `ops/lxd-fleet/up.sh` at 2026-10-13T12:18Z, IP 2.29.110.40 |
| Occupancy marker | `v2026-10-0-rc-20.manual-faultfleet-485-local-55692` |
| Run window | 2026-10-13T12:26:52Z → 12:32:33Z (UTC) |
| Run dir | `lxd-stage2-v2026.10.0-rc.20-20261013T122652` (pinned worktree scratch) |
| Guest | `s2-v2026-10-0-rc-20-0-https-only-egress`, forked from `s2-base-v2026-10-0-rc-20-installed-v2026-09-3-standalone/checkpoint` |
| Guest OS | Ubuntu 26.04.1 LTS, kernel 7.0.0-30-generic, nftables v1.1.6 |

## nft rules as listed inside the guest

Captured with `lxc exec <guest> -- nft list table inet statbus_https_only` at 12:30:56Z, after `apply_https_only_egress` and before the upgrade:

```
table inet statbus_https_only {
	chain output {
		type filter hook output priority filter; policy accept;
		ip daddr != { 10.0.0.0/8, 127.0.0.0/8, 172.16.0.0/12, 192.168.0.0/16 } tcp dport 80 reject with icmp port-unreachable
		ip6 daddr != { ::1, fc00::/7, fe80::/10 } tcp dport 80 reject with icmpv6 port-unreachable
	}
}
```

Policy probes (scenario log):

```
✓ deliberate IPv4 TCP/80 connection refused: http://93.184.216.34/statbus-http-egress-mutation
VACUOUS: VM has no IPv6 route to 2606:2800:220:1:248:1893:25c8:1946; the inet-family nft rule was installed and checked, but no IPv6 TCP/80 connection can be attempted
```

The IPv6 refusal is **not** exercised live: the LXD bridge is created with `ipv6.address=none` (`ops/lxd-fleet/up.sh`). The IPv6 rule is present in the listing above and is covered offline by `tests/https-only-egress-test.sh` and the missing-IPv6-rule mutation.

## docker-proxy loopback health

```
✓ at-install docker-proxy health path allowed (HTTP 404)
✓ health check passed (attempt 1, code=200, 1×5s)
✓ CA-verified HTTPS /rest/ (HTTP 200)
```

HTTP 404 from `http://127.0.0.1:80/rest/` is the expected non-`000` answer: the connection reached Caddy through docker-proxy (host → container IP:80, not NATed), which a too-wide rule would refuse with `000`.

## Install result

```
── initial install at v2026.09.3 ──
historical baseline v2026.09.3 already established by real installer in checkpoint
```

Honest scope: on the LXD backend the v2026.09.3 install is performed by the real installer **when the checkpoint is built**, which is before this fork applies the egress policy. So this run proves the installed box, its docker-proxy health path and the **upgrade** under HTTPS-only egress. It does not prove a from-scratch install under HTTPS-only egress (the Hetzner VM path applied the policy before installing).

## Upgrade result

```
Registered candidate v2026.10.0-rc.20 (commit bce5bf39)
[data] ✓ candidate images ready
Scheduled upgrade to v2026.10.0-rc.20
✓ upgrade in_progress (t+0s)
✓ upgrade reached state='completed' (t+53s)
✓ demo-data counts match snapshot (statistical_unit=126,legal_unit=23,establishment=50,statistical_history=1430)
✓ upgrade flag file absent
✓ health check passed (attempt 1, code=200, 1×5s)
✓ CA-verified HTTPS /rest/ (HTTP 200)
NRestarts: baseline=0 final=1 delta=1
PASS: 0-happy-upgrade (supervised unattended path completed cleanly; data intact; unit stable)
```

The candidate's images were pulled, verified and applied with public TCP/80 rejected.

## Defect found by the first attempt (run 0, discarded)

The first attempt (12:19Z, harness `f0137449d`) also reported PASS, but it was **false-green**: `lxd_checkpoint_for_scenario` only recognised the `exec "$(dirname "$0")/X.sh"` delegation spelling. This scenario delegates as `exec bash "$SCENARIO_DIR/0-happy-upgrade.sh"`, so it forked the candidate's own `installed-v2026.10.0-rc.20-standalone` checkpoint. The "upgrade" was rc.20 → rc.20 (`Installed version v2026.10.0-rc.20 already recorded in upgrade table (no change)`). Fixed in `55731c7cb`. `tests/lxd-checkpoint-identity-test.sh` failed before the fix (`FAIL: 0-https-only-egress checkpoint = installed-v2099.01.1-rc.1-standalone`) and passes after it. Only run 1 above is evidence.

## Workstation-run artefact

Locally `run-forks.sh`'s RC freshness lookup printed `REFUSE: guest SSH destination git@github.com does not match fork IP` and `::warning title=RC freshness unknown`: the backend's ssh shim intercepted `git ls-remote` against an ssh-URL `origin`. CI checks out over https, so this does not occur there. rc.20 was the newest RC at run time (`git ls-remote` checked separately before the run).
