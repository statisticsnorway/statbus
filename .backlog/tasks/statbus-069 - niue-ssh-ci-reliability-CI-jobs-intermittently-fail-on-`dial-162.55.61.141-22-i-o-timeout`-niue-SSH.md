---
id: STATBUS-069
title: >-
  niue-ssh-ci-reliability: CI jobs intermittently fail on `dial 162.55.61.141:22
  i/o timeout` (niue SSH)
status: To Do
assignee: []
created_date: '2026-06-17 07:59'
updated_date: '2026-07-06 17:31'
labels:
  - tooling
  - not-install-upgrade
dependencies: []
ordinal: 69000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
> NORTH STAR: trustworthy CI — gated jobs must not fail on infrastructure noise.
> BENEFIT: CI stops flapping on SSH timeouts to niue; gated jobs stop failing spuriously.
> HYPOTHESIS (King): crowdsec on niue blocks GitHub's shared-runner IP ranges; operator verifying read-only now; fix direction if confirmed = self-hosted runner on the host via docker compose (King's proven pattern from another project).
> COMPLEXITY: operator-verify then engineer-substantial.
> DEPENDS ON: nothing.

---

CI jobs that SSH to niue.statbus.org (162.55.61.141) intermittently fail with `dial tcp 162.55.61.141:22: i/o timeout` (30s connect timeout) BEFORE any work runs — a niue SSH reachability/latency issue, NOT a code failure.

CONCRETE INSTANCES (2026-06-17):
- notify-all-clouds.yaml: `notify (statbus_jo)` leg failed on push 55cb5c959 (the other 6 slots succeeded → niue up, single-slot/transient); SUCCEEDED on the next push c3e00f5f4.
- pg_regress.yaml (`Run tests on remote server`): failed on push 73ea5210f — the SSH dial timed out before checkout/tests; Fast Tests (same SQL, different path) PASSED, corroborating code is fine. Manual re-run unblocked it.

IMPACT: each timeout reds a strict CI gate and costs a manual re-run; if it recurs it can gate the rc.04 release gate spuriously. pg_regress runs ON niue via SSH (`git fetch && git checkout <sha> && ./dev.sh continous-integration-test`), so its reliability is coupled to niue SSH reachability.

NOT URGENT (transient, self-recovers on re-run). If the pattern persists, investigate: niue SSH/network load, sshd connection limits, or whether pg_regress should run somewhere less coupled to a production host. Architect flagged the external root cause is real (no-flaky-tests: it's niue SSH dial reliability, not a flaky test). Foreman observed both instances firsthand.
<!-- SECTION:DESCRIPTION:END -->

## Comments

<!-- COMMENTS:BEGIN -->
author: foreman
created: 2026-07-06 17:31
---
HYPOTHESIS CONFIRMED (2026-07-06, root inspection authorized by the King). Mechanism found and active: crowdsec on niue subscribes to the community blocklist (CAPI) — 38,822 active ban decisions, 38,821 from the community list, INVISIBLE in the default `cscli decisions list` (which showed zero; they appear only with -a). The community list currently bans hundreds of IPs inside the Azure prefixes GitHub Actions runners use: 399 in 20.x, 206 in 52.x, 72 in 4.x, 67 in 13.x, 64 in 40.x (cross-checked against api.github.com/meta actions ranges). A runner drawing a banned IP is firewall-DROPPED → exactly the observed `dial tcp 162.55.61.141:22: i/o timeout` signature (drop, not refusal), intermittent by IP lottery — the symptom fired again TODAY at 15:33 UTC during the board pushes. Local alert history (24 retained, all ssh brute-force from CN/VN/HK/etc.) contains zero Azure entries — the bans come from the community feed, not local detections, which is why they never showed in local alerts. FIX DIRECTION (King's proven pattern): self-hosted runner ON niue via docker compose — CI traffic never crosses the public SSH gate. Deliberately NOT whitelisting GitHub's ranges in crowdsec: attackers use GitHub runners for SSH attacks (the very reason the community list bans these IPs); a whitelist would re-open that door. COMPLEXITY: engineer-substantial. Buildable when prioritized.
---
<!-- COMMENTS:END -->
