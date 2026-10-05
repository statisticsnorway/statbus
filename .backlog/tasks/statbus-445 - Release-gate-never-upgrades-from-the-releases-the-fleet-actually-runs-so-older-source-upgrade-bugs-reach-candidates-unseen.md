---
id: STATBUS-445
title: >-
  Release gate never upgrades from the releases the fleet actually runs, so
  older-source upgrade bugs reach candidates unseen
status: Done
assignee: []
created_date: '2026-10-03 14:55'
updated_date: '2026-10-05 09:38'
labels:
  - release
  - testing
  - upgrade
  - install-recovery
dependencies: []
references:
  - STATBUS-436
  - STATBUS-441
  - STATBUS-443
  - STATBUS-444
priority: high
---

## Issue

Every upgrade proof on the release ladder starts from one of two sources:
- the **newest stable**: smoke `0-happy-upgrade` installs v2026.09.3, then upgrades
- the **candidate itself**: the arcs install A = the candidate commit, then upgrade to fixture B/C

No gate ever upgrades from an **older** release. That is exactly where three bugs in a row lived. All three were found only by the on-demand STATBUS-436 proof, which happens to start on v2026.09.2:
- STATBUS-441: the inline claim uses post-382 SQL and stops at 42703 on a pre-382 schema.
- STATBUS-443: the inline capture refuses after an installer checkout leaves `.env` at the source tag.
- STATBUS-444: install crash recovery regenerates config without `--migrate-legacy-secrets` and refuses on 09.2-era `.env.config` secrets.

rc.12 and rc.13 passed every machine gate (rc.13: arcs 41/41, fleet, smoke, hardening, dev canary) while carrying these bugs.

## Evidence: the fleet is mostly on older releases (read-only probe 2026-10-03 14:53 UTC)

| box | `sb --version` | legacy secrets in `.env.config` |
|---|---|---|
| demo | v2026.09.2 | 2 |
| et | v2026.09.0 | 2 |
| ug | v2026.09.0 | 2 |
| jo | v2026.08.0 | 2 |
| ma | v2026.09.3 | 0 |
| rune (no) | v2026.09.3-rc.17 | 0 |
| dev | v2026.10.0-rc.13 | 0 |

The gate's only upgrade source (09.3) matches 2 of the 7 boxes.

## Principled fix (owner ruling 2026-10-03: no big steps)

The class is narrow: **an old release's on-disk files meet new install, upgrade or recovery code.** That calls for small tests that feed each supported release's real file shapes to every entry point that reads them, not a VM matrix.

1. **Fixtures with provenance.** Capture the `.env.config` (and `.env.credentials` where one exists) that each supported release actually generates (v2026.08.0, v2026.09.0, v2026.09.2, v2026.09.3), using that release's own generator. A checked-in capture script and README record the tag, commit and command. Secret values become placeholders, but the keys stay exactly where that release puts them.
2. **One table-driven Go test:** every fixture against every config-generation entry point used by install, upgrade and recovery:
   - the Settings step (`GenerateForInstallInDir`)
   - the service's `config generate --migrate-legacy-secrets`
   - the install crash-recovery call
   - any other site in the STATBUS-444 audit

   Generation must succeed and the secrets must land in `.env.credentials`. Drive the real entry points, not copies.
3. **Same pattern for the other two old-era shapes, which already have this layer:**
   - **old schema:** the STATBUS-441 livedb fixture replays migrations through the predecessor and runs the real claim
   - **old `.env` tag vs new HEAD:** the STATBUS-443 shim regression

   New old-era inputs join the same table when found.

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Per-release config fixtures exist with recorded provenance, produced by each release's own generator.
- [x] #2 A table-driven Go test runs every fixture through every install/upgrade/recovery config-generation entry point and asserts success plus secret migration.
- [x] #3 Proven RED on master for the 09.2/09.0/08.0 fixtures through install crash recovery (STATBUS-444), and GREEN with the 444 fix.
- [x] #4 When a new stable is released, its fixture is added. This is recorded as a step in doc/releases.md (the stable-promotion checklist).
<!-- AC:END -->

## Implementation Notes

2026-10-05 09:38 UTC: the work is two commits, independently reviewed (MERGE, `tmp/445-review.md`), merged on top of the STATBUS-444 commits.

- **40bef6ae3 `config:` product fix.** Strict generation used to create `.env.credentials`, with a generated SEQ_API_KEY, before it refused on legacy secrets. The later migration then kept that generated value, so the operator's real key was lost. Config is now validated first. A focused test fails with the old order and passes with the fix.
- **c38b2a83c fixtures and table test.** It holds the real `.env.config`/`.env.credentials` that v2026.08.0, 09.0, 09.2 and 09.3 generate, captured with each tag's own generator. A provenance README and `capture.sh` record how. The table test feeds every fixture to every install, upgrade and recovery config-generation entry point, plus rollback cases (08.0, 09.0, 09.2) through the real snapshot and restore functions: byte-exact, 0600. A line in `doc/releases.md` adds a new stable's fixture to the promotion checklist.

Without the 444 fix the crash-recovery cases fail (on master the seam did not exist; the test was red at build time). With it they pass.
