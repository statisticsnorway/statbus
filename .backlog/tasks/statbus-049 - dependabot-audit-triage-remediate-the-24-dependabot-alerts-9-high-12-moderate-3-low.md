---
id: STATBUS-049
title: >-
  dependabot-audit: triage + remediate the 24 dependabot alerts (9 high / 12
  moderate / 3 low)
status: To Do
assignee:
  - engineer
created_date: '2026-06-13 11:58'
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
