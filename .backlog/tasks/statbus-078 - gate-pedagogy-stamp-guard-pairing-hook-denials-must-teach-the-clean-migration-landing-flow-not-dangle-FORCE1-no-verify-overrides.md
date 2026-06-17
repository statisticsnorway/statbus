---
id: STATBUS-078
title: >-
  gate-pedagogy: stamp-guard + pairing-hook denials must teach the clean
  migration-landing flow, not dangle FORCE=1 / --no-verify overrides
status: To Do
assignee:
  - '@engineer'
created_date: '2026-06-17 18:19'
labels:
  - dx
  - safety-machinery
  - migrations
  - rc.04
  - pedagogy
dependencies:
  - STATBUS-077
references:
  - 'dev.sh:134-253'
  - 'cli/cmd/types.go:140-214'
  - '.githooks/pre-commit:63-112'
  - cli/internal/migrate/at_head.go
priority: high
ordinal: 78000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
King directive (2026-06-17): "hooks exist to PREVENT dirty workarounds … the educational text is not good enough since people consider workarounds — we need to improve the denial and improve the learning … point to the right procedure, suggesting the right commands." Triggered when landing the STATBUS-077 from_commit_sha DROP migration: the foreman reached for `git commit --no-verify` and the engineer for `FORCE=1` — both led there by the gate denials.

ROOT CAUSE: both stamp-guard denials (dev.sh check_stamp_guard:153-160 + cli/cmd/types.go checkTypesStampGuard:152-161) end with `Override: commit or stash the changes, or set FORCE=1 to bypass.` — they list three escapes and never the actual procedure, and frame the one that works ("FORCE=1 to bypass") as cheating. For the canonical land-a-migration flow all three are wrong/blocked: `commit` → blocked by the pre-commit pairing hook (.githooks/pre-commit:81-112, migration ⟹ doc/db staged together); `stash` → breaks generate-doc-db's assert-db-at-head (seed vs on-disk head, cli/internal/migrate/at_head.go); `FORCE=1` → the only one that works, but reads as a bypass. So the HAPPY PATH itself is forced through an override — that is why agents reach for workarounds.

CLEAN PROCEDURE (the right commands, from the code):
1. ./sb migrate new --description "…"  + edit up/down
2. ./sb migrate up                     (apply to dev DB)
3. ./sb migrate up --target seed && ./dev.sh create-test-template   (bring seed to head so assert-db-at-head passes)
4. ./dev.sh generate-doc-db && ./sb types generate                 (regen schema docs + types)
5. git add migrations/ doc/db/ app/src/lib/database.types.ts        (stage migration + regen TOGETHER)
6. git commit                          (pre-commit hook validates the pairing — NO --no-verify)
Today step 4 requires FORCE=1 (stamp guard refuses dirty migrations/).

RECOMMENDED FIX (foreman → King for review BEFORE implementing):
(1) ROOT: change check_stamp_guard (dev.sh) + checkTypesStampGuard (cli/cmd/types.go) so a dirty migrations/ at generate-time RUNS the regen but SKIPS writing the freshness stamp (a stamp is never written while dirty → can never lie), instead of REFUSING. Then step 4 needs no FORCE=1 — the canonical flow is override-free; the pre-commit pairing hook stays the correctness gate. SANITY-CHECK: (a) other caller ./dev.sh test fast (scope migrations,test); (b) release.go preflight reading the stamp; (c) the SKIP/catch-22 path dev.sh:207-234; confirm no weakening of release-time honesty.
(2) WORDS: rewrite both stamp-guard denials to TEACH steps 1-6 with exact commands; rewrite the pre-commit hook --no-verify note (.githooks/pre-commit:106-107) to say plainly that --no-verify on a SCHEMA migration ships incomplete work (a migration with no reviewable schema diff) and is ONLY for data-only migrations.

OWNERS: engineer drafts denial wording (from his own "what sent me to FORCE=1" experience, per the King) + verdicts the RUN-without-stamp change + 3 sanity checks; foreman owns the procedure/commands; architect byte-reviews; KING reviews the design before any gate is edited. STATBUS-077's migration lands through this same clean flow once it's in.
<!-- SECTION:DESCRIPTION:END -->
