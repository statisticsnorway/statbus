---
id: STATBUS-083
title: >-
  vm-exec-multiline-hardening: VM_EXEC silently mangles multi-line if/then via
  printf-%q transport — base64 it or audit all multi-line sites
status: To Do
assignee: []
created_date: '2026-06-17 22:48'
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
