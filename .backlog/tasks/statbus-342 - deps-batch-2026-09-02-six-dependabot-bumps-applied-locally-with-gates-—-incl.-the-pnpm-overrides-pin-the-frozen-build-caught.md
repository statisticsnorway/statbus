---
id: STATBUS-342
title: >-
  deps-batch-2026-09-02: six dependabot bumps applied locally with gates — incl.
  the pnpm-overrides pin the frozen build caught
status: Done
assignee: []
created_date: '2026-09-02 12:36'
labels: []
dependencies: []
priority: medium
type: chore
ordinal: 335000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Retroactive record (foreman process miss, King-corrected 2026-09-02: dispatched from chat without a ticket — the rule going forward is ticket-first for every dispatched unit).

Done: the six open Dependabot PRs applied LOCALLY per the standing procedure (never merged on GitHub): Go go-pkcs12 0.7.1→0.7.2; npm next 16.2.9→16.2.11, sharp 0.34.5→0.35.0, undici 7.28.0→7.29.0, mermaid 11.15.0→11.16.1, postcss(dev) 8.5.15→8.5.23. Gates: go vet/build/test all packages; app tsc, lint (accepted baseline), jest 22/22, production build. Commits: 'deps: dependabot batch applied locally with gates' + follow-up 'deps: postcss override pinned to 8.5.23 too' — the app Dockerfile's pnpm install --frozen-lockfile caught that package.json's pnpm overrides pin stayed at the old postcss while the lockfile moved; local unfrozen installs had masked it. Lesson recorded: bump procedure must include any overrides/resolutions pins, and the acceptance check is a FROZEN install.

Rode v2026.09.0-rc.03.
<!-- SECTION:DESCRIPTION:END -->
