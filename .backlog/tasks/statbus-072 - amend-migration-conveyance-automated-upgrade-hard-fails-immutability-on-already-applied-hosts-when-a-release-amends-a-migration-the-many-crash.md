---
id: STATBUS-072
title: >-
  amend-migration-conveyance: automated upgrade hard-fails immutability on
  already-applied hosts when a release amends a migration (the many crash)
status: To Do
assignee: []
created_date: '2026-06-17 09:21'
labels:
  - upgrade
  - migrate
  - data-integrity
  - immutability
  - untested
  - king-flagged
dependencies: []
priority: high
ordinal: 72000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
KING-FLAGGED (2026-06-17) + foreman-verified in code. The "amend an already-released migration" path is real but its AUTOMATIC conveyance is MISSING, so the more-important host population crashes on automated upgrade.

THE SCENARIO: a released migration V is buggy (crashes on some hosts, succeeded on others). We cut a NEW release that AMENDS V in place (allowed via the immutability exemption) so it no longer fails. Two host populations must both survive the automated upgrade to that release:
- THE FEW (crashed on V -> V unrecorded): corrected release re-runs V -> works. Likely fine (no content-hash mismatch; V never recorded).
- THE MANY (already applied V, recorded with OLD bytes): automated upgrade -> eagerContentHashCheck sees V's recorded hash != V's new file hash -> MISMATCH. Must SKIP V (re-stamp) without crashing. *** THIS IS THE BUG ***

VERIFIED MECHANISM (cli/internal/migrate/migrate.go eagerContentHashCheck :1312-1413; cli/internal/release/immutability.go):
- The exemption EXISTS: STATBUS_CIRCUMVENT_IMMUTABLE_MIGRATION names versions; on a content-hash mismatch for a listed version, the check RE-STAMPS db.migration.content_hash to the new file bytes and continues (no crash, :1380-1397). Any OTHER released-tag migration that changed -> HARD FAIL immutability violation (:1404-1413).
- THE GAP: that env var is MANUAL ("Operators set this only when they MUST modify an already-released migration in place" — immutability.go:13-15). Repo-wide sweep: STATBUS_CIRCUMVENT_IMMUTABLE_MIGRATION appears in exactly 3 files, ALL READS (migrate.go runtime, release_verify.go + release.go at RC-cut). NOTHING SETS IT automatically — not the upgrade service, not install, not the deploy workflows, no release manifest. The upgrade service spawns ./sb migrate up inheriting an env where it was never set.
- CONSEQUENCE: in the automated-upgrade model (operators only run install.sh; upgrades automatic), no one sets the circumvent flag per-host -> the MANY hard-fail the immutability gate on the automated upgrade to an amended-migration release.

WHY IT MATTERS MORE THAN THE CANARY (STATBUS-067): the canary bites the FEW (hosts that crash mid-migration). This bites the MANY (every host that applied the migration). King: "the path where we change a migration already applied without crashing is actually more important — that would bite the many; the other would bite the few."

FIX DIRECTION (design TBD): the RELEASE must auto-convey "migration V is the amended one, accept its new bytes" to the runtime automated upgrade (a release manifest / upgrade-row field / config the upgrade reads -> sets circumvent for V), so the re-stamp fires WITHOUT a human touching each host. Then BOTH paths (many: re-stamp+skip without crash; few: re-run corrected) work automatically.

TEST (via STATBUS-071 real-upgrade-arc framework): the most important Shape-1 variant — adds the dimension the foreman missed: the migration ALREADY SUCCEEDED on most hosts (not just failed). Arc: install A (with migration V) -> V applied+recorded on host-many; on host-few V crashed (unrecorded) -> cut amended release C (V fixed in place + auto-conveyed circumvent) -> automated upgrade BOTH hosts -> many: skip V no crash (re-stamp); few: re-run V(fixed) works. Both reach healthy at C, data intact.

NOT an rc.04 blocker (rc.04 amends no migration). But high-priority product bug + completely untested. Investigate the intended workflow (is manual-set the design? it conflicts with the automated model), then auto-convey + test.
<!-- SECTION:DESCRIPTION:END -->
