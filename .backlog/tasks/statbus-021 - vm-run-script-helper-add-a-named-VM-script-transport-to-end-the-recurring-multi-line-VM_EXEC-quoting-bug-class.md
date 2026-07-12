---
id: STATBUS-021
title: >-
  vm-run-script-helper: add a named VM-script transport to end the recurring
  multi-line VM_EXEC quoting bug class
status: To Do
assignee: []
created_date: '2026-06-09 23:30'
updated_date: '2026-07-12 02:43'
labels:
  - install-recovery
  - harness
  - tech-debt
dependencies: []
ordinal: 21000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
> NORTH STAR: end the recurring multi-line VM quoting bug class with one named, safe script transport.
> BENEFIT: a bug class that has burned at least five separate debugging cycles (heredoc collapse, dash-quoting collapse, base64 double-eval, var-mangle, sudo-$ expansion) becomes structurally impossible — every future scenario author gets one safe helper instead of re-discovering the trap on a paid VM.
> STAGE: Testing foundation.
> COMPLEXITY: mechanic-simple (helper + migrate the audited call sites + make VM_EXEC refuse multi-line loudly).
> DEPENDS ON: nothing.

---

The install-recovery harness's `VM_EXEC` (printf %q + `ssh sudo -i -u statbus -- <args>`) is UNSAFE for multi-line script bodies, and agents keep reaching for it. It has caused at least 4 distinct failures this campaign: the heredoc-newline collapse (watchdog-reconnect drop-in), the dash `$'...'` ssh-quoting collapse (8 blocks, fixed bdb0cd763), the base64 sudo-i double-eval disaster (0/18, reverted eff26f815), and the seed_pre_upgrade_snapshot var-mangle (run 27239835249 — `$vol`/`$dest` emptied; fixed f31ce6f86 by switching to the file-based transport).

ROOT CAUSE: `VM_EXEC bash -c '<body>'` works only for bodies that are pure literals / locally-spliced values (e.g. `cd ~/statbus; cp ...; git commit`). It MANGLES any body that assigns a shell var on the VM and references it later (the printf %q + sudo -i -- bash -c arg layer drops/empties them). The robust pattern already exists in the codebase: write the body to a local temp file with a QUOTED heredoc, `scp -O` it, `chmod 0644`, run via `ssh ... 'sudo -i -u statbus bash /tmp/x.sh'` (bash reads the FILE → no -c re-parse). It's used by install_statbus_in_vm (vm-bootstrap.sh:565-574), _run_sql_file_in_vm, fabricate_scheduled_upgrade_row, seed_pre_upgrade_snapshot (post-fix), and the assertions' `<<<` stdin.

WORK: add a single named helper (e.g. `vm_run_script <vm> <<'EOF' ... EOF` or a function taking a heredoc) to test/install-recovery/lib that encapsulates the mktemp+scp+chmod+ssh-bash-file transport, so scenario authors never hand-roll multi-line `VM_EXEC bash -c` again. Optionally make `VM_EXEC` loudly refuse a multi-line argument (fail fast with a pointer to vm_run_script) so the trap can't recur silently. Then migrate the remaining hand-rolled multi-line VM_EXEC bodies to it (audit: grep `VM_EXEC bash -c` across scenarios). Harness-only; no product change.

NOT blocking the NO rollout or STATBUS-017 — this is durable harness hardening to stop the bug class.
<!-- SECTION:DESCRIPTION:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
MERGED IN from STATBUS-083 (King-ratified consolidation 2026-07-03): same multi-line-quoting root cause — VM_EXEC's printf-%q + sudo bash -c transport mangles multi-line if/then into syntax errors; the fix is ONE base64 VM-script transport covering both tasks' symptoms.
<!-- SECTION:NOTES:END -->

## Comments

<!-- COMMENTS:BEGIN -->
author: architect
created: 2026-07-12 02:43
---
RULED (architect, 2026-07-12). Verified first: VM_EXEC (vm-bootstrap.sh:370) %q-quotes its args but hands them to `sudo -i -u statbus` — a LOGIN shell that re-evaluates, which is the documented trap right above it (:360-366: literal-$ content comes back silently expanded; the prescribed remedy is already named there — local file + scp, the health-park callback precedent). Also verified: of 511 VM_EXEC call sites today, ZERO are multi-line — the dangerous instances were already hand-converted to scp over the campaign; the ticket's job is to make the safe pattern a named tool and the unsafe one impossible.

(1) TRANSPORT SHAPE: scp-a-file, NEVER heredoc-to-VM-file — constructing the file ON the VM via an ssh heredoc routes the content through the same ssh→sudo→shell evaluation layers that caused the class; writing LOCALLY (call site uses a QUOTED heredoc delimiter, so content stays byte-literal) and scp-ing is the only shape where no shell ever evaluates the payload. Two helpers: `VM_SCRIPT <local-script-path> [args...]` — scp to a unique /tmp/vm-script-<basename>-$$.sh on the VM, chmod 0755, execute as the statbus user via the existing VM_EXEC (args are plain %q-safe words), propagate rc; remote file KEPT (ephemeral VM, forensics-friendly). And `VM_SCRIPT_INLINE <name>` reading the script body from STDIN — writes it to a local tmp file first, then delegates to VM_SCRIPT; the call-site pattern is `VM_SCRIPT_INLINE probe <<'EOF' ... EOF` (quoted delimiter mandatory — say so in the helper's comment).

(2) LOCATION: vm-bootstrap.sh, directly beside VM_EXEC — it is transport, not arc logic; the existing warning comment (:360-366) is rewritten to point at VM_SCRIPT as the named tool instead of describing the manual pattern.

(3) GUARD (the 158 pattern): YES — VM_EXEC refuses when any argument contains a newline: refuse loudly, exit 1, banner names VM_SCRIPT/VM_SCRIPT_INLINE as the remedy (house contention-banner style). Newline-only, NOT $-detection: single-line args legitimately carry locally-expanded $vars everywhere (407 bash -c sites), and literal-$-for-later is syntactically indistinguishable from intended expansion — a $-guard would be all false positives. The newline guard has ZERO false positives on the current 511 sites (verified: none multi-line).

(4) MIGRATION POLICY: no sweep — there is nothing to sweep (zero multi-line sites, verified). New code MUST use VM_SCRIPT for any script-shaped payload (multi-line, or content with literal-$ semantics); existing single-line sites stay untouched; the guard makes the dangerous form structurally impossible going forward. This is the same two-layer economics as 158: a refuse-loudly guard at the entry point + the named safe tool.

(5) SIZING + ORACLE: MECHANIC-SIMPLE, with 158 as the direct precedent (same author-pattern: guard + banner + live verification). Oracle, three legs live on one scratch VM exactly like 158's: (i) happy path inert — an existing arc's single-line VM_EXEC calls run unchanged; (ii) the guard refuses a synthetic multi-line VM_EXEC with the banner; (iii) ROUND-TRIP FIDELITY — VM_SCRIPT ships a script whose body contains a literal unexpanded `$CANARY` reference plus a multi-line construct, executes it, and asserts the VM-side output proves the content arrived byte-literal (the exact class the sudo -i trap corrupted). bash -n + shellcheck on the touched lib.
---
<!-- COMMENTS:END -->
