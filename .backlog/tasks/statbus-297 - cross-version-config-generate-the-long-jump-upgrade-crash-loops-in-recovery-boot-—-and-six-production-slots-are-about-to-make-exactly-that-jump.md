---
id: STATBUS-297
title: >-
  cross-version-config-generate: the long-jump upgrade crash-loops in recovery
  boot — and six production slots are about to make exactly that jump
status: In Progress
assignee:
  - '@engineer'
created_date: '2026-08-28 11:48'
labels:
  - upgrade
  - cli
  - install-recovery
dependencies: []
priority: high
type: bug
ordinal: 290000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
NORTH STAR: a box that has not upgraded in weeks must still be able to take the newest release. The cross-version-rename-handoff arc — the only scenario that tests a LONG jump (fixed pre-rename base 730b5001c, 2026-07-13; every other arc tests one hop) — now crash-loops on that jump, and six PRODUCTION slots are about to attempt exactly it.

WHAT THE JOURNAL SHOWS (rc.15 fleet run 33163032285, job 98822620080; captured by 296's journal-first diagnostics on their first live fire): install of the target succeeds, binary swaps, fresh process boots into recovery ("Recovery boot ... restoring target tree + regenerating config before db up"), then `./sb config generate` exits 1 — "Error: pre-flight: regenerate config before db up: exit status 1" — and systemd restarts into the identical failure every ~30s until its rate limiter gives up (restart counters 1-5, then "Start request repeated too quickly"). The box ends with db down. NO panic, NO SIGSEGV — the listener (294) is a total non-participant, confirmed by clean listenLoop shutdown lines.

THE MISSING BYTE, and the sub-fix this ticket carries: service.go:2094-2096 captures `./sb config generate`'s CombinedOutput and DISCARDS it before wrapping the error — unlike the git-checkout call four lines above, which appends the output. The journal therefore says "exit status 1" and not WHY. Sub-fix: append the trimmed output, same as the sibling call site.

ATTRIBUTION HISTORY, corrected: this scenario redded at rc.11 (attributed to 293's lottery — wrong for this scenario), rc.14 (attributed to 294's listener crash by fingerprint-sharing with transient-db-backoff — wrong for this scenario), and now rc.15, where the journal finally names the real mechanism. The scenario was green before rc.11's fleet, so the BREAKING CHANGE entered master in a bounded window: after the last green fleet (~2026-08-19) and before rc.11 (2026-08-27). Something in that window made config generate fail against a box carrying July-era config state.

WHY THIS MAY GATE THE FLEET PROMOTION, not just a test: STATBUS-287's six production slots (tcc, demo, et, jo, ma, ug) run v2026.07.0-rc.03 built 2026-07-13 — the SAME era as this scenario's pinned base. When the stable is promoted and channel-following delivers it, those six boxes attempt EXACTLY this jump. If the crash loop reproduces there, six production boxes wedge with db down. The arc is not a broken test; it is the only test standing where the fleet is about to walk.

FIRST STEPS: (1) reproduce locally — current `./sb config generate` against a July-era .env.config/.env state (no VM needed), capture the actual error; (2) search config.go's changes in the bounded window for a new hard requirement (key, file, validation) that old boxes cannot satisfy; (3) the output-append sub-fix so the next journal names the error itself; (4) then rule the remedy (config generate must self-heal the missing state, or the upgrade path must supply it) — architect.

WHAT IS ACHIEVED: the long-jump upgrade path works for the boxes that actually need it, and the error that was discarded is discarded nowhere.
<!-- SECTION:DESCRIPTION:END -->
