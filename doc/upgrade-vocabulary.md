# Upgrade & Recovery Vocabulary — the slug glossary

The single source of truth for naming the upgrade/recovery system. One concept → one **slug** → one **message**.

## The regime

- **slug** — kebab-case, condensed, precise. Used *everywhere it is terse*: code identifiers and variables, log keys, doc anchors, diagram labels, test/scenario names, commit scopes. This is the greppable canonical name.
- **message** — the slug elaborated into plain language for humans: log lines, the operator UI, error output. Add stop-words; keep the meaning identical to the slug.
- Example: slug `db-backup` → message *"Backing up the database…"*.

This is not new — the fault-injection classes and test scenarios already work this way
(`killed-by-system-during-preswap-backup`, `restore-db-stall-watchdog`,
`migration-slower-than-systemd-unit-timeout`). This glossary extends that proven pattern to the whole vocabulary.

### The one constraint — serialized values (UNDER REVISION)

> **King decision (2026-06-22):** we *will* change the on-disk serialized values to match the slugs (clean break), with a **clean restart** on an old/unrecognized sentinel instead of read-both. Whether that is safe hinges on the upgrade being restart-safe from a post-swap, partially-migrated state — provable only by the install-recovery arcs. Until that lands, the bytes below are the conservative default; slug / identifier / prose renames are already free.

The slug is free everywhere **except the values written to disk**. The `Phase` stored in the
`upgrade-sentinel` file (today: `""`, `post_swap`, `resuming`) is read back by the **new** sb
during recovery — so a box that is mid-upgrade has the *old* bytes on disk. Those **stored values
keep their current bytes** (or the new sb reads both old+new) even as the slug, the identifier, and
the prose around them change. Renaming a serialized value breaks recovery across the version boundary.

### Code identifiers follow the slug

`db-backup` → `dbBackup()` / `DBBackup`; `upgrade-sentinel` → `upgradeSentinel`;
`stop-clients` → `stopClients()`. The code rename is the **last** pass, once the slugs are locked.

---

## Phases (which `sb` is running)

| slug | meaning | message |
|---|---|---|
| `old-sb-upgrading` | the **old** sb binary is running the upgrade (before the swap; was `Phase=PreSwap`) | "still on the old sb — preparing the upgrade" |
| `old-sb-swap` | the **old** sb's last act — it performs the swap, then `exit 42` (the point of no return) | "switching to the new sb" |
| `new-sb-swapped` | the **new** sb is swapped in — checking whether it's already converged before migrating (stored `post_swap`; was `Phase=PostSwap`) | "now running the new sb" |
| `new-sb-upgrading` | the **new** sb binary is running the post-swap migrations (stored `resuming`; was `Phase=Resuming`) | "now on the new sb — finishing the upgrade" |
## Upgrade states (the `public.upgrade.state` column)

One candidate row per release; `state` walks the lifecycle below. **Three actors** drive it:

- **CLI** — `./sb upgrade …` (ops / automation)
- **web** — the admin UI, browser → PostgREST `/rest/upgrade`, RLS-gated to `admin_user`. The Next.js app has **no** server-side writers — every web transition is a direct browser→DB PATCH.
- **service** — the upgrade daemon (execution + automatic transitions)

| state (stored value) | meaning | entered by | message |
|---|---|---|---|
| `available` | a candidate exists, ready to schedule | CLI `check`/`register` · service discovery | "upgrade available" |
| `scheduled` | queued to run | CLI `schedule` · web | "upgrade scheduled" |
| `in_progress` | `sb` is running it | service · `./sb install` (atomic claim) | "upgrade in progress" |
| `completed` | finished on the new version | service · `./sb install` (the `executeUpgrade` pipeline) | "upgrade completed" |
| `rolled_back` | undone cleanly; healthy on the old version | service · `./sb install` (the `executeUpgrade` pipeline) | "rolled back to the old version" |
| `failed` | the rollback's restore **also** failed; needs a human | service · `./sb install` (the `executeUpgrade` pipeline) | "upgrade failed — needs hands-on recovery" |
| `skipped` | operator opted out before it ran — reversible (web `restore` → `available`) | web (human, pre-run) | "upgrade skipped" |
| `dismissed` | operator acknowledged a failed/rolled-back row into history | web (human, post-failure) | "upgrade dismissed" |
| `superseded` | auto-retired when a newer candidate was scheduled | service (automatic) | "superseded by a newer version" |

```
  available  ← CLI check/register · service discovery
     │ schedule (CLI · web)
     ▼
  scheduled  ← CLI · web
     │ claim (service)
     ▼
  in_progress ─(service)─┬─► completed
                         ├─► rolled_back
                         └─► failed

  terminal dispositions (off the run path):
     available          ─skip(web)─►    skipped   ─restore(web)─► available
     failed/rolled_back ─dismiss(web)─► dismissed
     older candidate    ─newer scheduled (service, auto)─► superseded
```

The disposition trio — how a candidate closes **without** completing:
- `skipped` — **human, pre-run**: opt out of an `available` candidate. Reversible (`restore` → `available`).
- `dismissed` — **human, post-failure**: acknowledge a `failed`/`rolled_back` row into history (guarded: only when `error` or `rolled_back_at` is set).
- `superseded` — **machine, automatic**: the service retires an older candidate when a newer one is scheduled.

Actor split, in one line: **CLI** creates candidates (check / register), schedules, and can run an upgrade *inline* (`./sb install`) · **web** is human curation (schedule / skip / restore / dismiss) · **service** polls + runs scheduled upgrades + auto-supersedes. Execution itself is the `executeUpgrade` pipeline, kicked off by the **service or `./sb install`** (both `sb`).

### What the row stores (26 columns — full catalog in `doc/db/table/public_upgrade.md`)

- **identity** — `id`, `commit_sha`, `committed_at`, `commit_tags`, `commit_version`, `release_status`, `summary` / `changes` / `release_url`
- **gating (own axis, not `state`)** — `has_migrations`, `docker_images_status` (building→ready→failed), `release_builds_status`, `docker_images_downloaded`
- **lifecycle timestamps** — `discovered_at`, `scheduled_at`, `started_at`, `completed_at`, `rolled_back_at`, `skipped_at`, `dismissed_at`, `superseded_at`
- **recovery** — `backup_path`, `log_relative_file_path`, `from_commit_version`, `error`

`docker_images_status` is a parallel axis: a candidate is `available` from creation while its images build/verify; image-readiness gates scheduling without being a `state` value.

## Scheduling

| slug | meaning | message |
|---|---|---|
| `claim-upgrade` | `sb` (the systemd service, **or** `./sb install` inline) atomically claims a `scheduled` upgrade and runs it (`executeUpgrade`) — race-safe: whichever invoker wins, the other bails | "picking up the scheduled upgrade" |

## Recovery — reading the state & deciding direction

| slug | meaning | message |
|---|---|---|
| `recorded-state` | what the system last **wrote down** — the `public.upgrade` row's state + the flag's recorded phase | "what the records say" |
| `observed-state` | what we **measure now** on the machine — binary (disk) + migrations (db) + liveness (flock); recovery reconciles this against `recorded-state` | "checking the real state on the machine" |
| `already-at-new` | verdict: already at the new version → finish forward | "already at the new version — completing" |
| `cannot-reach-new` | verdict: confirmed it can't reach the new version → roll back | "unable to upgrade — rolling back" |
| `position-unreadable` | can't read where we are — DB unreachable, or the target commit not present. **Not** "continue on a guess": it's a failed step → classify it (*when a step fails*) — recognised transient → `backoff-retry`, unrecognised → stop for a person | "can't read the state yet — retrying, then rolling back if it won't clear" |

## Recovery — the actions

| slug | meaning | message |
|---|---|---|
| `continue-upgrade` | go forward: do the remaining upgrade steps | "continuing the upgrade to the new version" |
| `complete-upgrade` | finish the leftover bookkeeping + mark completed (already at new) | "completing the upgrade" |
| `roll-back` | undo: restore the `db-snapshot`, return to the old version | "rolling back to the old version" |

## Recovery — when a step fails (classify the error)

One rule: **retry only what we know is temporary; roll back what we know is permanent; stop on anything we can't name.** Safe by default — a failure on neither curated list is `unknown-error`, never retried or rolled back blindly.

| slug | what it is | what recovery does |
|---|---|---|
| `intermittent-error` | a failure we recognise as **temporary** (the cases below) | `backoff-retry` — cleared → continue, else → `roll-back` |
| `persistent-error` | a failure we recognise as **permanent** — fails the same way every time (e.g. a migration that can't apply) | `roll-back`, zero retries — a retry can't change a deterministic outcome |
| `unknown-error` | a failure we **don't recognise** | stop for a person — don't act on what we can't name |

The outcome is uniform — every intermittent case ends in **continue (it cleared)** or **`roll-back` (it didn't)**, never a spin. One strategy, `backoff-retry`, covers both cases; what's tuned to the probe is the parameters **and how we decide a single try has failed** — a quick wall-clock cap for the instant connection check, a *stall* (no-progress) detector for the fetch, so a slow-but-still-moving transfer is never cancelled.

### `intermittent-error` cases → `backoff-retry`

| case slug | probe (what we retry) | when one try has failed | gap between tries | overall budget → `roll-back` |
|---|---|---|---|---|
| `db-unreachable` | open a connection + a trivial query (healthy = sub-second) | wall-clock **5s** — a quick check, never a transfer | 1s → 2s → 4s → 8s → 16s → 30s cap | **≈ 5 min** (~12 tries) |
| `commit-not-fetched` | one `git fetch` of the target version (healthy = seconds to minutes) | a **stall** — *no progress* for ~60s (git's low-speed timeout); a transfer that's still moving is **never** cancelled, however long it legitimately takes | 10s → 30s → 60s cap | **≈ 15 min total** |

The health checks (DB-health, REST-ready, the health-RPC probe) already do their own bounded waits → rollback on exhaustion — not new work, and not on this path.

### `backoff-retry` — the loop

- try the probe → **succeeds → continue**
- the try fails — a quick probe exceeds its wall-clock cap, **or** a fetch *stalls* (no progress for ~60s) — → wait the growing gap, then try again. A fetch that is still transferring is left alone, however many minutes it takes.
- a **heartbeat** every loop, so the watchdog (120s) can't kill it mid-wait
- **overall budget exhausted → it's no longer temporary → `roll-back`** (data-safe — the read-only window means a rollback loses nothing)

Why the fetch retries rather than taking one long attempt: a fetch can take minutes *and* hit an intermittent network drop — one attempt forfeits the whole upgrade to a single blip, where a few backed-off retries ride it out. The per-try check is a **stall, not a deadline**, so a healthy slow transfer is never killed; and if the network is genuinely down, the overall budget still bounds it and we roll back.

This in-process retry is **new** — today these transients exit straight to a systemd restart. It sits **in front of** the existing systemd-StartLimit backstop: a known transient that exhausts **rolls back** here; the systemd backstop remains only for the genuinely **`unknown`** case (an unrecognised error or unreadable phase). An exhausted *known* transient must never fall through to the old restart-until-stuck loop — that was the spin we removed.

*Exact caps, stall thresholds, gaps, and budgets reconcile at build and are validated by the install-recovery arcs; the shape — retry-with-backoff, stall-not-deadline for transfers, exhaust → roll back — is fixed.*

## Recovery — the two human stops

Recovery is autonomous everywhere except two cases — both principled, both rare.

| slug | what it is | message |
|---|---|---|
| `unknown` | we can't read the situation — an **`unknown-error`** (unrecognised) or an **unreadable phase** in the marker. We don't act on what we can't name → stop, stay loud, wait for a person (mechanically: the upgrade stays `in_progress` and the systemd-StartLimit backstop surfaces it) | "an unrecognised situation — stopping for a person" |
| `restore-broke` | a rollback was chosen, but the **restore itself failed** — the snapshot couldn't be put back, so the box can't reach a runnable state. Hands-on regardless (the `failed` upgrade-state) | "the rollback's restore failed — needs hands-on recovery" |

## Mechanisms & artifacts

| slug | meaning | message |
|---|---|---|
| `upgrade-in-progress` | the single file (`tmp/upgrade-in-progress.json`) that marks an upgrade mid-flight and records it — who started it (install vs service), which version, how far. It's the one lock point: flocked, so only one upgrade runs at a time, and whether the lock can be taken separates a crashed upgrade (free) from a running one (held) — no stored PID, the flock is the sole liveness signal | "the upgrade-in-progress file" |
| `db-snapshot` | the rollback artifact — an **offline** copy of the stopped DB volume (rsync'd to `pre-upgrade-active/`), taken before the upgrade; what a rollback restores | "the database snapshot" |
| `db-snapshot-backup` | take the `db-snapshot`: stop the DB, then rsync the volume — offline, so it's trivially consistent (no WAL, no `pg_backup`) | "backing up the database" |
| `db-snapshot-restore` | restore the `db-snapshot` on rollback: rsync the saved copy back | "restoring the database from the snapshot" |
| `db-dump` | the **logical**, space-optimised backup for **regular scheduled** runs — `pg_dump -Fc` → `pg_restore`; a separate path from the snapshot (logical, not physical) | "the scheduled database dump" |
| `stop-app-services` | stop the application services — worker, app and rest — before a migration, so they release the database (their connections + table locks); the database itself stays up | "stopping the application services (worker, app and rest)" |
| `restart-loop` | the failure where the service restarts forever, never finishing (the "rune wedge") | "stuck restarting in a loop" |
| `heartbeat` | the `WATCHDOG=1` ping that tells systemd the service is alive | "heartbeat" |

## Kept as-is — precise standard terms, used verbatim

`flock` (the OS lock taken on the `upgrade-in-progress` file) · `watchdog` (systemd's term; its ping is the `heartbeat`) · `exit 42` (the code-level `sb-swap` signal) · `systemd` · `pg_restore`, `pg_locks`, `AccessShareLock`, `AccessExclusiveLock` (Postgres terms).

---

*Status: the recovery vocabulary — the read pair, the direction verdicts, the error classification ("when a step fails": `intermittent-error` / `persistent-error` / `unknown-error`, the one `backoff-retry` strategy + its two cases), and the two human stops (`unknown`, `restore-broke`) — is **ratified (King, 2026-06-27)** and crystallised here + in `doc/upgrade-recovery-model.md`. Mechanisms & artifacts are now locked too (`upgrade-in-progress`, `db-snapshot` / `db-snapshot-backup` / `db-snapshot-restore` / `db-dump`, `stop-app-services`, `restart-loop`, `heartbeat`); the `restore-broke` operator output is specced (STATBUS-111). The vocabulary is **complete** — only open item is the on-disk Phase serialization values (parked, arc-gated). Applying the vocabulary to docs/diagrams/code/logs is STATBUS-107. Once a section locks, apply one site at a time per STATBUS-107 — docs → diagrams → code/variables → logs.*
