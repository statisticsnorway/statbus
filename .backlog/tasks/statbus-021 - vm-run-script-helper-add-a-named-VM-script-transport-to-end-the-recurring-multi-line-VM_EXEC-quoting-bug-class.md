---
id: STATBUS-021
title: >-
  vm-run-script-helper: add a named VM-script transport to end the recurring
  multi-line VM_EXEC quoting bug class
status: To Do
assignee: []
created_date: '2026-06-09 23:30'
updated_date: '2026-07-03 10:45'
labels:
  - install-recovery
  - harness
  - tech-debt
dependencies: []
priority: medium
ordinal: 21000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
The install-recovery harness's `VM_EXEC` (printf %q + `ssh sudo -i -u statbus -- <args>`) is UNSAFE for multi-line script bodies, and agents keep reaching for it. It has caused at least 4 distinct failures this campaign: the heredoc-newline collapse (watchdog-reconnect drop-in), the dash `$'...'` ssh-quoting collapse (8 blocks, fixed bdb0cd763), the base64 sudo-i double-eval disaster (0/18, reverted eff26f815), and the seed_pre_upgrade_snapshot var-mangle (run 27239835249 — `$vol`/`$dest` emptied; fixed f31ce6f86 by switching to the file-based transport).

ROOT CAUSE: `VM_EXEC bash -c '<body>'` works only for bodies that are pure literals / locally-spliced values (e.g. `cd ~/statbus; cp ...; git commit`). It MANGLES any body that assigns a shell var on the VM and references it later (the printf %q + sudo -i -- bash -c arg layer drops/empties them). The robust pattern already exists in the codebase: write the body to a local temp file with a QUOTED heredoc, `scp -O` it, `chmod 0644`, run via `ssh ... 'sudo -i -u statbus bash /tmp/x.sh'` (bash reads the FILE → no -c re-parse). It's used by install_statbus_in_vm (vm-bootstrap.sh:565-574), _run_sql_file_in_vm, fabricate_scheduled_upgrade_row, seed_pre_upgrade_snapshot (post-fix), and the assertions' `<<<` stdin.

WORK: add a single named helper (e.g. `vm_run_script <vm> <<'EOF' ... EOF` or a function taking a heredoc) to test/install-recovery/lib that encapsulates the mktemp+scp+chmod+ssh-bash-file transport, so scenario authors never hand-roll multi-line `VM_EXEC bash -c` again. Optionally make `VM_EXEC` loudly refuse a multi-line argument (fail fast with a pointer to vm_run_script) so the trap can't recur silently. Then migrate the remaining hand-rolled multi-line VM_EXEC bodies to it (audit: grep `VM_EXEC bash -c` across scenarios). Harness-only; no product change.

NOT blocking the NO rollout or STATBUS-017 — this is durable harness hardening to stop the bug class.
<!-- SECTION:DESCRIPTION:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
MERGED IN from STATBUS-083 (King-ratified consolidation 2026-07-03): same multi-line-quoting root cause — VM_EXEC's printf-%q + sudo bash -c transport mangles multi-line if/then into syntax errors; the fix is ONE base64 VM-script transport covering both tasks' symptoms.
<!-- SECTION:NOTES:END -->
