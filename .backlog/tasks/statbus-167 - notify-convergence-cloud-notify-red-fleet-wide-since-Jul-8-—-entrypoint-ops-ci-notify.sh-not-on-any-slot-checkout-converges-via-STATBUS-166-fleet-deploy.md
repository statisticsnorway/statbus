---
id: STATBUS-167
title: >-
  notify-convergence: cloud-notify red fleet-wide since Jul 8 — entrypoint
  ops/ci-notify.sh not on any slot checkout; converges via STATBUS-166 + fleet
  deploy
status: To Do
assignee: []
created_date: '2026-07-12 15:57'
labels:
  - ci
  - not-install-upgrade
dependencies:
  - STATBUS-166
priority: medium
ordinal: 168000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
> NORTH STAR: every red CI leg names a real, current problem — no leg stays red for a known, converging reason without a ticket saying so.
> BENEFIT: the fleet's Slack upgrade notifications come back; the 40-runs-red notify history gets a documented cause + a verifiable green endpoint.
> STAGE: convergence tracking — no code change expected on this ticket itself.
> COMPLEXITY: observation + one verification run after the fleet deploys.
> DEPENDS ON: STATBUS-166 (exit-21 restamp remedy), then the STATBUS-123 deploy sequence.

DIAGNOSIS (foreman, 2026-07-12): notify-all-clouds has failed on every run since 2026-07-08 — ALL 40 recorded runs are failures. Two stacked causes, peeled in order:
1. (fixed today, af42633f3) The runner-online canary gated notify on the withdrawn RUNNER_STATUS_TOKEN PAT → every leg SKIPPED, masking cause 2.
2. (the real one, older) c07439b5b (2026-07-08) converted notify to call the byte-stable server-side entrypoint `~/statbus/ops/ci-notify.sh`, and niue's live /etc/sshdoers pins ONLY that path for the notify users. But every slot checkout is at c4692562e (2026-06-18) — the entrypoint file has NEVER existed on any slot. Every leg: `bash: /home/statbus_<slot>/statbus/ops/ci-notify.sh: No such file or directory` (exit 127). Verified live on statbus_dev (ssh read).

THE STRUCTURAL LESSON (for doc-026/123 review): a workflow that calls a file in the SLOT's checkout creates a deployment-ordering dependency — the entrypoint pattern is right long-term (behavior evolves in git, only the path is pinned) but it cannot bootstrap: the referencing workflow went live ~1 month before any slot could have the file. Future server-side entrypoints must ship to the fleet BEFORE the caller starts referencing them.

WHY NO INTERIM FIX EXISTS: reverting the workflow to the old inline `./sb upgrade check` would be REJECTED by sshdo (that byte-string is no longer in the allowlist); hand-placing ci-notify.sh on slots is a manual server write (forbidden — and the file legitimately arrives via upgrade). Deploys are unaffected (deploy-to-* uses its own pinned `apply-latest` line — proven working by today's dev deploy attempt).

CONVERGENCE PATH: STATBUS-166 ships the restamp conveyance → dev deploys green (the 123 gate) → fleet deploy sequence resumes → each slot's checkout advances past c07439b5b → its notify leg goes green. Notify red-per-slot until that slot upgrades.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 After the fleet deploy, one notify-all-clouds run is fully green (all 7 legs) — run ID cited on this ticket
- [ ] #2 Any slot deliberately NOT deployed is named here with its expected-red status instead of being left ambient
- [ ] #3 The structural lesson (server-side entrypoints ship before callers reference them) is recorded in doc-026 or the STATBUS-123 design doc — one home, cited here
<!-- AC:END -->
