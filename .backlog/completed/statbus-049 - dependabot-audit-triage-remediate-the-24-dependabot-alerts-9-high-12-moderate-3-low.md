---
id: STATBUS-049
title: >-
  dependabot-audit: triage + remediate the 24 dependabot alerts (9 high / 12
  moderate / 3 low)
status: Done
assignee:
  - engineer
created_date: '2026-06-13 11:58'
updated_date: '2026-06-13 12:22'
labels:
  - security
  - dependencies
  - tech-debt
dependencies:
  - STATBUS-048
references:
  - 'https://github.com/statisticsnorway/statbus/security/dependabot'
priority: high
ordinal: 49000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
GitHub dependabot reports 24 open vulnerability alerts on the default branch: 9 high, 12 moderate, 3 low. Surfaced 2026-06-13 on a master push. https://github.com/statisticsnorway/statbus/security/dependabot

The King wants a DETAILED pass — understand each alert, not a blind auto-bump. Queued AFTER STATBUS-048 (the engineer's current task); foreman routes the engineer here once 048 lands.

## Work
- Pull the full list: `gh api /repos/statisticsnorway/statbus/dependabot/alerts --paginate` (or the dependabot UI). Note the ecosystem per alert — likely a mix of Go modules (cli/go.mod) and the Node/pnpm app (app/package.json), possibly Docker base images.
- For EACH alert: identify the dependency + version, the CVE + severity, direct vs transitive, and whether our usage is actually exposed (or it's a transitive dep on an unreachable path).
- Remediate: bump to the fixed version where safe, running that ecosystem's gates after each bump (go test ./... for Go; the app's build/lint/test for pnpm). For anything needing a breaking update or a real code change, surface it for review rather than forcing it.
- Deliverable: a per-alert triage summary (fixed / deferred-with-reason / not-applicable-with-reason) + the dependency bumps, reported to foreman for review + commit. Don't silently dismiss alerts — document the call on each.

## Coordination
Go-module bumps (cli/go.mod) can ripple into the architect's in-flight cli/internal/upgrade work — coordinate with the foreman before bumping Go deps if the architect is still mid-flight there. pnpm bumps (app/) are disjoint.
<!-- SECTION:DESCRIPTION:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
ENGINEER (2026-06-13): 23/24 alerts FIXED (npm, app/) + verified; 1 (Go pgx) HELD for foreman coordination. Full per-alert triage: tmp/dependabot-triage-049.md.

NPM (23 alerts, 2 files changed, awaiting foreman review+commit — do-not-self-commit):
- app/package.json: direct bumps next ^16.2.6, mermaid ^11.15.0, postcss ^8.5.10; pnpm.overrides added for transitive vulns @rvf/set-get ^7.0.2, brace-expansion ^5.0.6, postcss ^8.5.10, tmp ^0.2.6, uuid ^11.1.1, ws ^8.20.1.
- app/pnpm-lock.yaml: regenerated (pnpm install, net -88 lines).
- ONE bump cleared 13 next alerts (#592-604) and one cleared 4 mermaid (#588-591); the rest one each (postcss #585, @rvf/set-get #587, tmp #608, brace-expansion #605, uuid #607, ws #606).
- Resolved (all >= patched, single instance): next@16.2.9, mermaid@11.15.0, postcss@8.5.15, @rvf/set-get@7.0.2, tmp@0.2.7, brace-expansion@5.0.6, uuid@11.1.1, ws@8.21.0.
- uuid note: override force-bumped exceljs's transitive uuid v8.3.2->v11.1.1 (only fix is in 11.1.1); VERIFIED safe — exceljs uses `const {v4}=require('uuid')`, the named export v11 retains; build passes.
- GATES GREEN: pnpm run tsc clean, pnpm run test 12/12, pnpm run build clean (incl ESLint).

GO (1 alert, HELD): #583 github.com/jackc/pgx/v5 v5.9.0 -> v5.9.2 (low, CVSS 0.0). Vuln needs non-default simple protocol; `grep QueryExecModeSimpleProtocol cli/` = 0 matches -> real exposure nil. Trivial patch bump recommended but NOT applied — cli/go.mod could collide with architect's in-flight cli/internal/upgrade. Awaiting foreman OK.

ENGINEER (2026-06-13): GO alert #583 (pgx) NOW DONE — foreman gave go-ahead (architect idle, item-A is logic in service.go, doesn't touch go.mod/go.sum). Applied as a SEPARATE change from the npm batch (for independent review/commit).

`go get github.com/jackc/pgx/v5@v5.9.2 && go mod tidy`. Diff is 2 files, minimal: cli/go.mod (v5.9.0->v5.9.2) + cli/go.sum (the 2 pgx hash lines). Notably pgx's own `go.mod h1:` hash is UNCHANGED across 5.9.0->5.9.2 (no transitive dep ripple; puddle/pgservicefile/pgpassfile untouched) — confirms pure patch.

No-ripple proof (cwd cli/): go vet=0, go build=0, go test ./...=0 — incl. cli/internal/upgrade (the pgx consumer) green. All 24 dependabot alerts now remediated (23 npm + 1 Go). Awaiting foreman commit of the Go change (do-not-self-commit).
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Resolved 2026-06-13. All 24 dependabot alerts remediated across two foreman-reviewed commits:
- fca1afe32 (23 npm) — one next→16.2.9 bump cleared 13 (proxy-bypass/SSRF/DoS/XSS/cache-poison, all genuinely reachable), mermaid→11.15.0 cleared 4, +6 transitive vulns via pnpm.overrides (existing pattern). The uuid v8→v11 major bump (only available fix) hand-verified safe (consumer uses the surviving named export). App tsc/test/build independently re-verified green by foreman.
- 44e8844c9 (1 Go) — pgx v5.9.0→v5.9.2 (advisory GHSA-j88v-2chj-qfwx, low/CVSS-0). Real exposure nil (QueryExecModeSimpleProtocol never used); applied for defense-in-depth. Patch bump, no transitive ripple (pgx go.mod hash unchanged); go vet/build/test green incl. cli/internal/upgrade.
Full per-alert triage in tmp/dependabot-triage-049.md — every alert fixed or documented, none silently dismissed. Foreman reviewed both diffs + independently re-verified all gates before each commit.
<!-- SECTION:FINAL_SUMMARY:END -->
