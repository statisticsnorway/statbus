---
id: STATBUS-060
title: >-
  install-sh-e2e-fidelity: harness recovery should run the real install.sh
  script, not the sb-install proxy
status: In Progress
assignee: []
created_date: '2026-06-15 23:44'
updated_date: '2026-06-16 11:57'
labels:
  - install-recovery
  - harness
  - fidelity
dependencies: []
priority: medium
ordinal: 60000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Harness-WIDE fidelity gap (surfaced during STATBUS-026 (b) review).

All install-recovery scenarios recover HEAD via `install_statbus_in_vm` (no version), which UPLOADS a host-built sb binary then runs the `sb install` subcommand (vm-bootstrap.sh:483-526). That proves the recovery LOGIC, but it does NOT exercise the operator's actual canonical action: `curl -fsSL https://statbus.org/install.sh | bash`, whose install.sh SCRIPT delivers the binary (release-asset download for tagged; image-extract for edge, added in f29e03a60) BEFORE running the sb install subcommand.

The King's North Star (STATBUS-039): the operator's ONLY action is install.sh. So a fully faithful recovery proof must run the actual install.sh script end-to-end (binary delivery + sb install), not the upload+sb-install proxy.

Scope: add a harness path that, for at least the legacy-recovery proof (2-preswap-checkout-kill-legacy) and ideally the supervised scenarios, runs the LOCAL repo's install.sh (the one carrying f29e03a60's edge image-extract) on the VM — `scp install.sh` + `bash install.sh --channel edge ...` — so the image-extract binary delivery is exercised. Caveat: install.sh edge does its own git ops (checkout -B current origin/master); verify they compose with a synthesised wedge state without disrupting the flag / pre-upgrade branch.

NOT blocking rc.03. f29e03a60 (install.sh edge image-extract) is reviewed code; this is end-to-end proof of it.
<!-- SECTION:DESCRIPTION:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
ID DISAMBIGUATION: this STATBUS-060 is a LATER REUSE of a freed id. Commits and STATBUS-059 dated 2026-06-15 that reference "STATBUS-060" mean the FORWARD-FIX (image-extract procurement + defer-checkout) — that work is DONE and its design/impl live in STATBUS-059 (commits 09ac1f7e4 / 2f52f3b7f / bb4848dd4). This 060 is the unrelated install.sh-end-to-end harness-fidelity follow-on described above.
<!-- SECTION:NOTES:END -->
