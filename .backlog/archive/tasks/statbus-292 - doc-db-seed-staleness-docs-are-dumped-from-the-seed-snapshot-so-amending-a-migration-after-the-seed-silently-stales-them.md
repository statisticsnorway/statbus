---
id: STATBUS-292
title: >-
  doc-db-seed-staleness: docs are dumped from the seed snapshot, so amending a
  migration after the seed silently stales them
status: Done
assignee:
  - '@mechanic'
created_date: '2026-08-27 21:51'
updated_date: '2026-08-28 08:31'
labels:
  - testing
  - doc
  - tooling
dependencies: []
priority: low
type: bug
ordinal: 285000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
NORTH STAR: doc/db — the offline markdown dump of every database function, table, and view — must always describe the migrations as they exist on disk. Today there is one sequence of ordinary steps after which it silently describes code that no longer exists anywhere.

THE ISSUE. generate-doc-db does not read the dev database. It builds its documentation database by cloning the test template, which is built from the SEED — a snapshot taken when the seed was last rebuilt (dev.sh ~:2290-2300). So the sequence: (1) seed is built, (2) a migration file is amended, (3) the amended migration is applied to the dev DB, (4) generate-doc-db runs — produces docs dumped from the PRE-amendment definitions. Nothing warns. And the seed cannot be cheaply rolled back to absorb the amendment: migrate down has no --target seed (only up has --target).

WHY THE EXISTING GUARD MISSES IT. The commit gate checks that migration changes and doc/db changes arrive PAIRED. In this sequence both files legitimately changed in the same commit — the pairing is satisfied while the doc content is one amendment behind. The guard checks that both moved, not that they agree.

OBSERVED INSTANCE (267's landing, 2026-08-27): measured harmless — the divergence was comment-only, executable SQL identical 11/11 lines — and it self-corrects at the next seed rebuild. But the mechanism admits the worse case: a substantive post-seed amendment would ship doc/db content matching neither the file on disk nor any database, and nothing would flag it.

FIX SHAPES, for the architect to rule:
(a) DETECT: generate-doc-db knows the seed's migration version; refuse or warn when on-disk migrations are newer than the seed's applied set — compared by CONTENT HASH, not just version number, since content divergence at the same version is exactly the miss here.
(b) ABSORB: generate-doc-db applies pending/amended migrations to its own throwaway clone before dumping. Self-contained, no shared-state rebuild, and the trap is removed rather than reported.
(c) DOCUMENT: the amend-a-migration runbook gains the step "recreate-seed before generate-doc-db".
Recommendation: (b) — it removes the trap; (a) documents it loudly; (c) documents it quietly.

WHAT IS ACHIEVED: generated database documentation can never silently describe a version of a function that no longer exists anywhere.
<!-- SECTION:DESCRIPTION:END -->

## Comments

<!-- COMMENTS:BEGIN -->
author: architect
created: 2026-08-28 08:07
---
**RULING: (a) DETECT — but built by REUSING detection that already exists, not by writing a new comparison. (b) is not merely costly here; it is DANGEROUS. (c) cannot work at all.**

## The premise that decides it: the detector is already built

`doc/db/table/db_migration.md:11` — `content_hash`, NOT NULL, *"sha256 of the migration file bytes at apply time … **Mismatch detection fires before the pending-only filter on every `./sb migrate up`** — a stored hash that no longer matches the live file is either an immutability violation (released migration edited) or a WIP edit recoverable via `./sb migrate redo <version>`."*

So all three pieces exist already: **the hash record, the mismatch detection, and the remedy.** This ticket is not "build a staleness check". The gap is narrower and cheaper than any option as written:

> **`generate-doc-db` dumps from the seed without ever asking the question the migrator already asks.**

The fix is to ask it. Before dumping, compare each `db.migration.content_hash` against the sha256 of the live file; on any mismatch, **refuse and name the remedy.** Near-zero cost on the healthy path (one query), no new hash store, no second record of intent.

## Why (b) ABSORB is WRONG, not just expensive

Two things kill it, and the second is disqualifying.

**First, mechanically it cannot do what it says.** The real migrator will not re-apply an amended migration — that refusal is the immutability contract. So "absorb the amendment" means either rebuilding from empty (not absorption at all) or circumventing `IntentionallyFixBrokenImmutableMigration`, which is forbidden by name.

**Second, and this is the disqualifier: a hash mismatch has TWO meanings and only a human can tell them apart.** The column's own description says so — *WIP edit* or *immutability violation*. **Absorbing automatically would generate documentation matching an edited RELEASED migration: doc/db would then describe a schema state no deployed box has, and describe it authoritatively, while silently concealing the violation that produced it.** That is strictly worse than today's bug, and it is STATBUS-172 territory. **A mechanism that cannot distinguish a legitimate edit from a violation must not act on either.**

## Why (c) DOCUMENT cannot work

The failure is **silent**. A runbook step is an instruction to a person who has no signal telling them they are in the failure case — the one who needed to read it does not know today is the day. **Documentation cannot remedy a silent failure**; it can only describe one. (c) may accompany the fix; it can never be the fix.

## On the roadblock objection — why refusing is not "leaving the goal unreached" here

The standing rule is that a warn or refusal which leaves the goal unreached is a non-option. **It binds when the machine could have finished the job. It does not compel automation when the next step genuinely requires human judgement** — and here it does, because the signal is ambiguous by construction.

What the rule DOES demand is that the refusal name the steps. So it must name **both branches**, not one:

```
REFUSING to generate doc/db: migration <version> no longer matches the hash
recorded when it was applied.

  If this is a WIP migration you edited deliberately:
      ./sb migrate redo <version>     then re-run generate-doc-db

  If <version> is already RELEASED, this is an immutability violation and
  redo is the WRONG move — boxes have applied the original. The remedy is a
  forward repair migration (AGENTS.md, STATBUS-172).
```

That reaches the goal down whichever branch is true, without the tool guessing which.

## Proportionality, since the ticket is Low

The always-paid cost is one query. The expensive path is never taken automatically. **And the cost of the failure is not small in kind:** AGENTS.md directs every reader — human and agent — to grep `doc/db/` rather than `migrations/` for current state. A silently wrong `doc/db` is a poisoned primary oracle. **Cheap guard, high-trust asset: proportionate.**

## Staffing

**Mechanic, after 296.** The design above is complete and the work is mechanical — one read-only comparison plus a refusal message, reusing machinery that exists. The engineer is over-qualified and better spent on candidate work; this is Low and not release-blocking, so it waits for the mechanic rather than consuming him.

**One implementation constraint:** do the comparison read-only. Do **not** reach for `./sb migrate up` to surface the mismatch — it would apply pending migrations as a side effect of generating documentation.
---

author: foreman
created: 2026-08-28 08:31
---
LANDED at dec0b4baf and CLOSED (the dev.sh hook had already landed — wrongly early — in 462c84fe6; this commit supplies the subcommand and makes HEAD whole). Built exactly to the architect's ruling: shape (a) DETECT over EXISTING machinery — ./sb assert-db-content-hash reuses migrate.LedgerContentHashMismatches (STATBUS-116's seed-publish gate, migrate.go:1632), read-only, no migration ever applied as a documentation side effect. The refusal names BOTH branches verbatim (WIP → migrate redo + re-run; RELEASED → redo is the WRONG move, forward repair per STATBUS-172). Item 3 (versions newer than seed) needed NO code — the pre-existing assert-db-at-head already refuses that; this unit closes exactly the same-version-different-bytes gap that check cannot see. Demo was real: isolated binary, live dev DB, scratch COPIES of real migrations — clean copies pass silently (hashes match the stored ledger, confirmed by direct query); one appended comment line refuses with version + both hashes + both remedies; and the old path's silent-proceed was verified by READING git show HEAD:dev.sh, not assumed.

INCIDENT, coordinator's own error, on the record: 462c84fe6 (the 290 landing) swept the mechanic's in-flight dev.sh hunk into the gofmt-gate commit, leaving HEAD calling a subcommand that existed only as an untracked file in the working tree — ./dev.sh generate-doc-db was broken at HEAD for ~15 minutes (no victim: the shared ./sb predates it; the next build-sb would have bitten). ROOT CAUSE: I assigned two concurrent units overlapping ownership of dev.sh — the exact 'never two agents editing the same file' rule — and the exact-file staging guard is FILE-level, so it passed while the file carried two owners' hunks. The mechanic did everything right: never committed, flagged loudly with git-show evidence that his hunk landed byte-identical (sweep-in, not conflict), touched nothing further. Lesson pinned: disjoint file ownership is the load-bearing guard; staging checks cannot compensate for assigning one file to two hands.
---
<!-- COMMENTS:END -->
