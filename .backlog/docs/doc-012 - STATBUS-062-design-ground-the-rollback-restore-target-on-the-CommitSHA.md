---
id: doc-012
title: 'STATBUS-062 design: ground the rollback restore target on the CommitSHA'
type: specification
created_date: '2026-06-16 10:08'
tags:
  - upgrade
  - recovery
  - foundational
  - architect-plan
  - STATBUS-062
---
# STATBUS-062 design — ground the rollback restore target on the CommitSHA

Architect design. Run by foreman → King BEFORE code. Vocabulary is a hard requirement (commit.go is sole source of truth).

## Glossary — the EXACT terms (from cli/internal/upgrade/commit.go)
| Term | Go type | Form | Authority | SQL |
|---|---|---|---|---|
| **CommitSHA** | `CommitSHA` | 40-char lowercase hex | AUTHORITATIVE identity; equality = same commit; **the only legal lookup key** | `public.upgrade.commit_sha` (text, CHECK `^[a-f0-9]{40}$`) |
| **CommitShort** | `CommitShort` | 8-char hex | display abbrev + CI Docker image tag; **never** equality/lookup | derived via `commitShort()` |
| **CommitVersion** | `CommitVersion` | `git describe --tags --always` (tag, `<tag>-N-g<short>`, or bare short) | human-facing label; **never** equality/lookup | `public.upgrade.commit_version` (display) |
| **ReleaseTag** | `ReleaseTag` | CalVer `vYYYY.MM.patch[-suffix]` | release tag only | — |

Constructors: `NewCommitSHA`, `NewCommitShort`, `NewReleaseTag`. No new shape predicates anywhere (TestGuards_UseTypedFields).

## The bug, in these terms
`from_commit_version` holds a **CommitVersion** (`d.version`), yet it is consumed as the **git-checkout restore target** — a lookup — in two places:
- `recoveryRollback` (service.go:2200): `SELECT from_commit_version` → `prev` → `d.rollback` → `restoreGitState`.
- `executeUpgrade` in-process (service.go:3857): `previousVersion := d.version` → all in-process `d.rollback`/`postSwapFailure`/`applyPostSwap` callers + `resumePostSwap` (4616).

A CommitVersion used for lookup violates the discipline ("never for equality or lookup"). Symptoms (STATBUS-061): "2026.05.2" doesn't resolve as a git ref (only the `v`-tag does) → restore reaches OLD only via the `pre-upgrade`-branch fallback; and `d.version` = the running binary's version = TARGET in a HEAD-recovery → restores the tree FORWARD (061 finding 1).

## Recommended approach — a SOURCE pair mirroring the TARGET pair
The table already models target identity as a pair: `commit_sha` (CommitSHA, authoritative) + `commit_version` (CommitVersion, display). Mirror it for the source.

1. **Schema (migration)** — ADD `from_commit_sha text` + CHECK `from_commit_sha IS NULL OR from_commit_sha ~ '^[a-f0-9]{40}$'` (mirror `chk_upgrade_commit_sha_is_full_hex`). KEEP `from_commit_version` (display). Regenerate `doc/db/table/public_upgrade.md` in the same commit.
2. **Capture (write)** — at the claim (`ExecuteUpgradeInline` service.go:1308, `executeScheduled` service.go:3498): `sourceSHA := NewCommitSHA(git rev-parse HEAD)`. The working tree is at the SOURCE here — the target checkout is deferred to the recovery boot (STATBUS-060) — so HEAD = source. This is the same commit `pre-upgrade` pins at service.go:3841. Persist `from_commit_sha = sourceSHA`; keep `from_commit_version = d.version` (display).
3. **Restore target (read)** — resolve from the CommitSHA, never the CommitVersion:
   - In-process: `previousVersion := string(sourceSHA)` (service.go:3857), replacing `d.version`. All in-process rollback callers inherit it.
   - Recovery: `recoveryRollback` (2200) reads `from_commit_sha` (validated `NewCommitSHA`) → `prev`; `prev := ""` default → `restoreGitStateFn` pre-upgrade fallback. **Supersedes the held rc.04 (iii).**
   - `resumePostSwap` (4616): read `from_commit_sha` → `previousVersion` for `applyPostSwap`.
4. **restoreGitStateFn** (5381) — unchanged. A CommitSHA always resolves; the `pre-upgrade` branch demotes to **pure defense-in-depth** (legacy rows + GC defense).
5. **Display consumers** — `from_commit_version` STAYS for display: admin UI "From:" (app/src/app/admin/upgrades/page.tsx:1225) and the fixup INSERT (cli/cmd/install.go:1932). Optional: add `from_commit_sha` to that INSERT for symmetry (low priority — completed rows never roll back).

## Back-compat (no backfill)
Existing rows: `from_commit_sha = NULL` (historical source SHAs unknown). A legacy in-flight row recovered by HEAD: `from_commit_sha` NULL → `prev := ""` → `restoreGitStateFn` → `pre-upgrade` branch (pinned by the OLD binary mid-upgrade) → OLD. ✓ No backfill needed. Down migration: drop `from_commit_sha`.

## Dissolves STATBUS-061's open risks
- **(a) checkout-kill risk GONE**: `from_commit_sha` = `git rev-parse HEAD` at claim = OLD (the tree), independent of the binary's version. So (a) recovers to OLD deterministically — the "from_commit_version stamped as a resolving TARGET" hazard cannot occur.
- **rc.04 (iii) SUBSUMED**: final `recoveryRollback` reads `from_commit_sha` → `prev := ""` → pre-upgrade.

## Harness split (King's option 3)
- `2-preswap-checkout-kill-legacy.sh` (genuine v2026.05.2): reproduce what v2026.05.2 ACTUALLY wrote — `from_commit_version="2026.05.2"` (CommitVersion), `from_commit_sha` NULL. Validates HEAD recovering a LEGACY row via the pre-upgrade fallback. [fidelity]
- HEAD/go-forward scenarios (part iv): `from_commit_sha` = source commit (real claim captures it, or the harness sets it). Validates the commit-grounded path.

## Sequencing (King decides)
- **Option A (recommended):** fold STATBUS-062 into the recovery fix — the RC ships (ii) + migration + capture + `recoveryRollback(from_commit_sha)`. Both 2-preswap scenarios pass cleanly, the (a) risk dissolves, (iii) is subsumed. Right foundation, once.
- **Option B:** rc.04 ships (ii) + (iii)-interim (`from_commit_version` → `prev:=""`→pre-upgrade) for the behavior reversal now; STATBUS-062 (`from_commit_sha`) as the next RC. Ships the behavior fix sooner; (a) handled by the harness until 062 lands.

## Critical files
- service.go: claim 1308 + 3498 (write `from_commit_sha`); `previousVersion := d.version` 3857 (→ sourceSHA); `recoveryRollback` 2200 (read `from_commit_sha`); `resumePostSwap` 4616 (read `from_commit_sha`); `restoreGitStateFn` 5381 (unchanged); pre-upgrade pin 3841 (the source commit).
- migrations/ new pair (ADD/DROP `from_commit_sha` + CHECK); doc/db/table/public_upgrade.md (regenerate).
- commit.go: `NewCommitSHA` (route through it; no new predicate).
- Display (unchanged): app/src/app/admin/upgrades/page.tsx:1225; cli/cmd/install.go:1932.

## Verification
- migrate up/down clean; `go test ./internal/upgrade ./internal/install ./internal/config`; `TestGuards_UseTypedFields` green.
- 0-happy green; both 2-preswap scenarios green (legacy → pre-upgrade fallback; checkout-kill → from_commit_sha=OLD direct).
- admin UI "From:" still renders the CommitVersion.

## Open questions (King)
1. ADD `from_commit_sha` (recommended — mirrors target pair, keeps display) vs RENAME `from_commit_version`→`from_commit_sha` (loses the display CommitVersion).
2. Sequencing A (fold into rc.04) vs B (rc.04 behavior-only, 062 next). Recommend A.
