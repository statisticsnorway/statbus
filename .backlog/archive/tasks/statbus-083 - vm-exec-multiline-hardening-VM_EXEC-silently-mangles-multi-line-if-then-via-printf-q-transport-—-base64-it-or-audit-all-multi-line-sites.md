---
id: STATBUS-083
title: >-
  vm-exec-multiline-hardening: VM_EXEC silently mangles multi-line if/then via
  printf-%q transport — base64 it or audit all multi-line sites
status: Done
assignee: []
created_date: '2026-06-17 22:48'
updated_date: '2026-07-03 10:45'
labels:
  - install-recovery
  - harness
  - hardening
  - follow-up
dependencies: []
references:
  - 'test/install-recovery/lib/vm-bootstrap.sh:358'
  - 'test/install-recovery/lib/wedge-helpers.sh:145'
priority: medium
ordinal: 83000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
WHAT: The harness's VM_EXEC helper (test/install-recovery/lib/vm-bootstrap.sh:358-361) transports commands to the VM via `printf '%q'` then `sudo -i -u statbus -- <args>`. `printf %q` emits ANSI-C `$'...\n...'` quoting for multi-line strings; the remote login shell (dash, via `sudo -i`) does NOT expand `$'...'`, so embedded newlines VANISH and a multi-line `if [ ... ]; then ... else ... fi` collapses onto one line → `syntax error near unexpected token 'then'` (rc=2). This SILENTLY mangles ANY `VM_EXEC bash -c '<multi-line if/then>'` site — it may error loudly (5-install-stage-a-killed-migrate.sh:94-110, the statistical_* psql-orphan block) OR run-wrong silently (simulate_advisory_zombie_empty_app, wedge-helpers.sh:145-160).

WHY: a class of latent harness bugs — any multi-line conditional sent through VM_EXEC is at risk. Surfaced during the rc.04 install-recovery triage (run 27715901866, 5-install red). The immediate offenders are fixed in the rc.04 batch by converting them to the established ssh-STDIN transport (mktemp the script, pipe via ssh stdin — newlines preserved, same pattern simulate_pool_exhaustion / simulate_worker_busy already use). THIS task is the BROADER hardening so new multi-line VM_EXEC sites can't silently regress.

STATUS / NON-GATING: not required for the rc.04 cut (the specific offenders get the ssh-STDIN fix in-batch). Architect-identified.

FIX SHAPE: either (a) harden VM_EXEC itself — base64-encode the script body and `base64 -d | bash` on the VM (newline-safe regardless of content), making all call sites robust; or (b) audit every `VM_EXEC bash -c '<multi-line>'` site and convert multi-line ones to ssh-STDIN. Prefer (a) — fixes the class at the transport, not site-by-site.
<!-- SECTION:DESCRIPTION:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
DEAD-CODE FINDING (foreman, 2026-06-18): the engineer's broader-audit flag surfaced 2 MORE multi-line-VM_EXEC sites with the vulnerable for/if-then/fi structure — wedge-helpers.sh: simulate_killed_migrate_subprocess (:33) and simulate_sigkill_upgrade_service (:304). BOTH have ZERO scenario callers (grepped all of test/install-recovery/ — only their own header comments). So they are DEAD CODE: never executed → not causing the rc.04 reds, not silently false-greening anything, not cut-relevant. RECOMMENDATION for this task: DELETE them (per 'remove wrong/dead code paths entirely') rather than convert — unless they're intended for a not-yet-written scenario (check git history / the author). The 2 LIVE offenders (5-install-stage-a:94-110 statistical_* orphan block + simulate_advisory_zombie_empty_app wedge-helpers.sh:145-160) are fixed via ssh-STDIN in the rc.04 #2 batch (separate from this task). This task remains the SYSTEMATIC class fix: base64-harden VM_EXEC's transport so no multi-line site (live or future) can silently collapse.

CLOSED-AS-MERGED into STATBUS-021 (one root cause: multi-line VM_EXEC quoting; King-ratified consolidation). The base64 transport lands under 021.
<!-- SECTION:NOTES:END -->
