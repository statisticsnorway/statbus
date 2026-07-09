---
id: STATBUS-128
title: >-
  sshdo-loud-rejection: sshdo must reject with a clear actionable error, never
  silent exit 1
status: To Do
assignee: []
created_date: '2026-07-03 10:35'
updated_date: '2026-07-09 00:23'
labels:
  - ops
  - ci
  - fail-fast
dependencies: []
ordinal: 129000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
> NORTH STAR: an allowlist rejection is loud and actionable at the caller — never weeks of bare exit 1.
> BENEFIT: the next /etc/sshdoers drift (guaranteed, since the allowlist pins exact script bytes) is diagnosed from one CI log line naming user + attempted command + allowlist path, instead of the three-week silent outage we just lived through.
> STAGE: Ops (the King's D5 ruling).
> COMPLEXITY: mixed — operator settles sshdo's provenance (package vs local script) and drafts the change; the King applies or approves the server write; same verification on rune.
> DEPENDS ON: nothing hard; pair with STATBUS-123's allowlist repair in the same niue session (soft).

---

King ruling (2026-07-02, D5 of the decision queue): the three-week notify-CI outage happened because `/usr/local/bin/sshdo` on niue rejects a non-allowlisted command SILENTLY — exit 1, zero output. "The job should have failed violently, according to the actionable fail-fast principle, so that we could have discovered this earlier, with clear error messages." Whitelisting runner IP ranges in CrowdSec was REJECTED as counterproductive (it would hide configuration errors).

WHAT: make sshdo emit a clear rejection to stderr before exiting non-zero — naming the user, the attempted command (truncated), and where the allowlist lives, e.g.:
  `sshdo: command not in allowlist for user statbus_ma (see /etc/sshdoers). Attempted: cd ~/statbus\nif [ -x ./sb ]...`
Then any CI job that trips the allowlist shows the cause in its log on the FIRST failure instead of weeks of bare exit-1.

GROUNDING: sshdo already logs rejections server-side (`sshdo[pid]: type="disallowed"` in auth.log — that's how we finally diagnosed it); the fix is surfacing that same information to the CALLER's stderr. /etc/sshdoers is hand-managed (repo copy tmp/niue-sshdoers); establish where sshdo itself comes from (package vs hand-installed script) before editing — if it's a distro package, a wrapper or config option may be the right shape instead of patching the binary/script in place.

CONSTRAINTS: server write on niue — foreman presents the concrete change to the King before applying (standing rule). Do not weaken the allowlist itself; only make its rejections loud. Also check rune.statbus.org for the same setup.

RELATED: the residual intermittent CI→niue TCP timeouts (CrowdSec community-feed bans of runner IPs) stay tracked in STATBUS-069 — explicitly NOT to be fixed by allowlisting per the King's ruling.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 A non-allowlisted command over SSH with the restricted key produces a one-line actionable error on the caller's stderr (visible in a CI job log) naming the user and pointing at the allowlist — demonstrated with a deliberate mismatched command
- [ ] #2 The allowlist's enforcement behavior is unchanged (rejection still exits non-zero; allowed commands unaffected)
- [ ] #3 The change's provenance is settled first: sshdo's origin (package vs local script) documented, and the fix applied in the shape that survives updates
- [ ] #4 Same verified on rune.statbus.org if it runs the same sshdo setup
<!-- AC:END -->

## Comments

<!-- COMMENTS:BEGIN -->
author: foreman
created: 2026-07-09 00:23
---
COST EVIDENCE (2026-07-09, ~23:56-00:25): sshdo's silent rejection burned a four-agent investigation tonight. The pg_regress workflow's SSH command was changed (STATBUS-150 self-heal step); /etc/sshdoers:44 allowlists statbus_test's CI key to exactly one command shape and silently rejected the new one — exit 1, zero output, ~2s, across four consecutive CI runs. The silence sent the investigation through THREE wrong hypotheses (drone-ssh multi-line handling — even shipped a relocation commit on that theory; self-hosted-runner assignment; CrowdSec GHA-range bans) before a root read of the journal + /etc/sshdoers named it. Compounding factor: an exoneration experiment tested the wrong KEY (the operator's own unrestricted key instead of the forced CI key) and falsely cleared the sshdo hypothesis early. A loud rejection — one stderr line naming the received command and the expected template — would have ended this in one CI-log read. That is this ticket's case, now with a measured cost.
---
<!-- COMMENTS:END -->
