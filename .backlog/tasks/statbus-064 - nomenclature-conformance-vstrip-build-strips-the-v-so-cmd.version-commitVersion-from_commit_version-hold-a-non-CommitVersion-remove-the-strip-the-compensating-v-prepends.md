---
id: STATBUS-064
title: >-
  nomenclature-conformance-vstrip: build strips the v so
  cmd.version/commitVersion/from_commit_version hold a non-CommitVersion; remove
  the strip + the compensating v-prepends
status: To Do
assignee: []
created_date: '2026-06-16 10:19'
labels:
  - nomenclature
  - upgrade
  - cli
  - foundational
dependencies: []
priority: high
ordinal: 64000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
DETERMINISM VIOLATION (King-caught + foreman-verified live 2026-06-16). A CommitVersion is, deterministically, `git describe --tags --always` output — which CARRIES the v. Verified: describe of release commit 50fd4325 = "v2026.05.2"; HEAD = "v2026.06.0-rc.03-26-g2d97ac800". The build STRIPS the v, so the value typed as upgrade.CommitVersion actually holds a v-LESS string that is NOT a CommitVersion. Calling that "CommitVersion" makes the name non-deterministic (sometimes with-v from git describe, sometimes v-less as stored) — the bane of confusion; it already misled the STATBUS-061 part-iv comment ("v2026.05.2" vs the real stored "2026.05.2").

## Sites (the deviation)
- STRIP (4): cli/Makefile:4 ; dev.sh:62 ; dev.sh:453 ; dev.sh:1969 — all `git describe … | sed 's/^v//'`.
- TYPE VIOLATION: cli/cmd/root.go:206 `commitVersion = upgrade.CommitVersion(version)` — wraps the v-less ldflag as a CommitVersion (a CommitVersion must carry the v).
- COMPENSATION (re-prepend "v", ≥2 — AUDIT for more): cli/internal/upgrade/github.go:119 `ValidateVersion("v" + bare)` ; cli/cmd/upgrade.go:459 `serviceVersion = "v" + version`. (dev.sh:58 comment admits the convention: "service.go adds 'v' back, avoiding double-v".)

## Fix (no new name — conform the code to the nomenclature)
1. Remove the 4 v-strips so cmd.version is a true CommitVersion (with v).
2. AUDIT + remove every compensating "v"-prepend (github.go:119, upgrade.go:459, + any others) — the value already carries the v; prepending would double it.
3. Result: upgrade.CommitVersion holds git-describe output verbatim everywhere → deterministic.

## Verify
`./sb --version` shows "v…"; go build/vet/test green; no double-v anywhere (grep `"vv"` / tag-construction sites); ValidateVersion + serviceVersion + any ReleaseTag construction still correct with the now-v-bearing value.

## Notes
- Does NOT break the genuine-v2026.05.2 legacy scenario: that release historically ALSO stripped → it stored "2026.05.2"; reproduce that v-less value as-is for historical fidelity (STATBUS-061 part iv/v).
- Rollback grounds on from_commit_sha (a CommitSHA) per STATBUS-062, so from_commit_version is display-only; this fix makes that display value a true CommitVersion.

OWNER: architect (nomenclature work). Pairs with STATBUS-062. Foreman reviews every diff; King ruling on the nomenclature recorded.
<!-- SECTION:DESCRIPTION:END -->
