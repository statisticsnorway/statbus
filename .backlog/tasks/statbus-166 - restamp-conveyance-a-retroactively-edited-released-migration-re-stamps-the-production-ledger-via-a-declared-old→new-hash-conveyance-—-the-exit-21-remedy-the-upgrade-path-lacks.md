---
id: STATBUS-166
title: >-
  release-cut-is-the-bless: boxes re-stamp gate-vetted migration bytes
  (content-level trust) — the exit-21 remedy
status: Done
assignee:
  - '@engineer'
created_date: '2026-07-12 15:25'
updated_date: '2026-07-12 23:24'
labels:
  - upgrade
  - migrations
  - production
  - fail-fast
dependencies: []
references:
  - cli/internal/migrate/migrate.go
  - cli/internal/release/immutability.go
  - doc-014
  - STATBUS-072
  - STATBUS-156
  - STATBUS-123
priority: high
ordinal: 167000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
> NORTH STAR: a gated release cut is the ONE bless for a retroactive edit to a released migration. Every box recognizes gate-vetted bytes and re-stamps itself through the NORMAL upgrade path; everything unvetted refuses loudly. No side channels, ever.
> FOUND: 2026-07-12 — dev deploy (row 323154) auto-rolled-back on `sb migrate up` exit 21: migration 20260218215337's ledger hash (cd82bc76) ≠ on-disk hash (71befa05) after the legitimate 8b5912a9a edit. Every deploy blocked at the dev gate (STATBUS-123).
> COMPLEXITY: engineer — one recognition branch + unit tests, plus one gated RC cut.

THE DESIGN (King, approved 2026-07-12 — also recorded BY DESIGN on `release.IntentionallyFixBrokenImmutableMigrationEnvVar`, immutability.go, so it is never re-derived again):

1. THE BLESS HAPPENS ONCE, AT THE RELEASE CUT. Cutting an RC/release refuses any changed released migration unless its version is named in `STATBUS_INTENTIONALLY_FIX_BROKEN_IMMUTABLE_MIGRATION` at the cut. Naming it is the deliberate, human, loud bless. (Shipped: release.go checkMigrationImmutability.)

2. THE EXISTENCE OF THE RELEASE **IS** THE BLESS. A cut release carrying changed released-migration bytes can only exist because a human blessed exactly those versions at the gate. There is deliberately NO second record — no declaration file, no sanctioned list on boxes, no runtime provenance re-check. (A file-conveyed declaration set was built once and retired, STATBUS-102; this ticket's first draft re-proposed it and was withdrawn.)

3. TRUST IS CONTENT-LEVEL, NOT COMMIT-LEVEL. On a mismatch for version V, the box's on-disk bytes are trusted iff some cut release carries exactly those bytes for V. A master commit carrying release-vetted bytes is trusted; a newer, not-yet-gated edit has bytes no release carries → refuse until the next gated cut. Self-consistent, no windows.

4. WHAT EACH CHANNEL DOES on a mismatch (migrate.go eagerContentHashCheck):
   - stable/prerelease — SHIPPED, unchanged: the whole diet is releases, so re-stamp trusting the gate, one loud line.
   - edge (dev: tests every master commit) — TO BUILD, the one code change: recognize vetted bytes. For mismatched version V with live hash H, check whether any release-shaped tag carries V with content hash H. Yes → re-stamp + the same loud line. No → refuse exactly as today. MUST work on a shallow clone: `git ls-remote` / tag fetch, never local tag-tree probes (documented unreliable on deployed boxes).
   - local — unchanged: a human is present; stop and tell them.

5. THE CONCRETE REMEDY for today's blockage: cut the next RC with `STATBUS_INTENTIONALLY_FIX_BROKEN_IMMUTABLE_MIGRATION=20260218215337`. Release-channel slots re-stamp on their next upgrade; dev re-stamps via the edge recognition branch. One blessed landing heals a box permanently for that edit (the ledger then matches all following commits).

ORACLE: (i) unit tests on the recognition branch — vetted bytes → re-stamp; ungated-edit bytes → refuse; version in no release → existing WIP guidance; (ii) THE REAL ONE: the dev deploy goes green through the completely normal path (STATBUS-123's dev gate); (iii) the loud re-stamp line appears exactly once per box per blessed edit.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Edge recognition branch: a mismatch whose on-disk bytes match that version's bytes in a cut release re-stamps with one loud line — proven to work on a shallow clone
- [x] #2 Unvetted bytes still hard-refuse (unit-tested: newer ungated edit; version in no release keeps existing WIP guidance)
- [x] #3 The next RC is cut with STATBUS_INTENTIONALLY_FIX_BROKEN_IMMUTABLE_MIGRATION=20260218215337 — the gated bless executed
- [x] #4 The dev deploy goes green through the normal path (the STATBUS-123 dev-gate oracle)
<!-- AC:END -->

## Comments

<!-- COMMENTS:BEGIN -->
author: foreman
created: 2026-07-12 21:33
---
REWRITTEN 2026-07-12 evening after the King's design review. The first draft's jsonl declaration file is WITHDRAWN — it re-introduced the side channel retired by STATBUS-102 ("declared intent lives ONLY in the env var at the cut", immutability.go). The King's design, played back and approved: the release cut is the single bless; the release's existence IS the bless; trust is content-level (his pushback sharpened commit-level to content-level: gated bytes are vetted bytes wherever a box got them). This is the FOURTH derivation of this design — to end that, the principle is now a BY DESIGN comment on release.IntentionallyFixBrokenImmutableMigrationEnvVar with a pointer at migrate.go's channel switch, committed alongside this rewrite. Architect's original ruling superseded by the King's own design.
---

author: architect (relayed by foreman)
created: 2026-07-12 21:36
---
ADVERSARIAL CHECK of the content-level rule (architect, 2026-07-12): two candidate holes examined, NEITHER blocks the build — the case is strengthened. (1) Reverse-direction re-stamp (a box on an older release's tree content-matching backward): benign — the cut's bless asserts hash-equivalence for ledger purposes, which is symmetric; the next forward upgrade re-stamps forward; the existing loud line already prints the old→new direction. (2) Bless-over-unknown-origin (rule matches only (V, live-hash), no constraint on what the ledger recorded): CLEARED, and it completes the soundness case — an unvetted-origin ledger entry for a released V cannot arise through the machinery (application-time refusal, FULL_REPLAY re-stamps from current bytes, manual writes forbidden doctrine). Origins are gated at APPLICATION time, which is exactly why origin-matching at RECOGNITION time — what the withdrawn jsonl design added — was redundant. The King's simpler rule is sound because the guard it seems to lack already exists upstream.
---

author: foreman
created: 2026-07-12 22:34
---
AC#3 EXECUTED (foreman, night shift, King-authorized RC cuts): v2026.07.0-rc.01 tagged and pushed at 143cece86 with STATBUS_INTENTIONALLY_FIX_BROKEN_IMMUTABLE_MIGRATION=20260218215337 at the cut — the gated bless. Full preflight green (log tmp/night-rc-cut-3.log): immutability gate blessed exactly the declared version and warned about the stable-shipped coordination (v2026.05.5); no other migrations modified since previous stable; fast tests green in CI (run 29211352635), types/tsc/app-build/doc-db stamps fresh at HEAD, images green (run 29211255733). The recognition code (edge branch, 684993683) and the blessed bytes are both on master and in the tag. Next: AC#4 — dev deploy dispatched; dev's edge box should hit the mismatch, find v2026.07.0-rc.01 carrying the blessed bytes, re-stamp with the loud line, and complete through the wholly normal path.
---

author: foreman
created: 2026-07-12 23:24
---
AC#4 PROVEN LIVE (2026-07-12 23:21 UTC) — the dev deploy went green through the wholly normal path, and every oracle leg landed: (i) upgrade row 324228 state='completed' at 23:21:15, target 17d47c5e2, box checkout confirmed at that commit, all five containers healthy, PostgREST ready in 2s; (ii) THE LOUD LINE, exactly once, in the daemon journal at 23:20:55 during the new binary's boot-migrate — '[migrate] ⟳ Intentionally fixing broken (immutable) migration 20260218215337: re-stamped content_hash cd82bc76 → 71befa05' — the edge recognition finding the blessed bytes in v2026.07.0-rc.01 exactly as the King designed; (iii) db.migration on dev now records 71befa05 for the version. Sequence note: the run's progress log shows 'All migrations are up to date' because the re-stamp + pending migrations landed in the new binary's boot-migrate during the 23:20:17→23:21:04 handoff window — the resume's later migrate step correctly found nothing left to do. The deploy path itself needed one same-night CI fix (the images-wait gate back onto a hosted job after the runs-on move — 17d47c5e2). STATBUS-123's dev gate is GREEN; the fleet sequence proceeds (rune-no next, then the remaining cloud slots), each expected to re-stamp via its own channel bless on this same RC.
---
<!-- COMMENTS:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
The release cut is the bless, end to end and live-proven. Design (King, fourth and final derivation — now a BY DESIGN code comment on the env var + the migrate channel switch): the bless for a retroactive edit to a released migration happens once, at the gated RC cut, by naming the version in STATBUS_INTENTIONALLY_FIX_BROKEN_IMMUTABLE_MIGRATION; the release's existence IS the bless (no declaration file — the withdrawn first draft's side channel stays retired); trust is content-level — bytes a cut release carries are gate-vetted wherever a box got them. Shipped: the edge recognition branch (release.ReleaseTagWithMigrationHash — shallow-clone-safe via ls-remote + tag fetch, newest-first; shared restampVettedMigration so release and edge announce identically), unit tests incl. a real --depth-1 clone, all refuse paths byte-unchanged. Executed: v2026.07.0-rc.01 cut with the bless. Proven live on dev (2026-07-12 23:21 UTC): row completed through the normal path, the loud re-stamp line exactly once (cd82bc76 → 71befa05 during boot-migrate), ledger re-stamped. Unblocks the whole STATBUS-123 deploy sequence and, through it, notify convergence (STATBUS-167).
<!-- SECTION:FINAL_SUMMARY:END -->
