---
id: STATBUS-069
title: >-
  niue-ssh-ci-reliability: CI jobs intermittently fail on `dial 162.55.61.141:22
  i/o timeout` (niue SSH)
status: To Do
assignee: []
created_date: '2026-06-17 07:59'
updated_date: '2026-07-03 10:45'
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
