# BRREG (Bronnoysund Register Centre) Integration

Norway-specific data pipelines for importing from BRREG, the Norwegian business register.

## Relationship Types (Roller)

BRREG publishes role relationships ("roller") between legal units. These map to `legal_rel_type` entries. **All imported role types form power groups** — any relationship edge, primary or not, contributes to clustering (see `doc/power-groups.md`, "Clustering and Hierarchy Algorithm"; proven by `test/sql/119_roller_data_power_groups.sql`, where an all-DTPR hierarchy forms its own power group). The `primary_influencer_only` flag controls cardinality (1:1 vs 1:N), the single-controller exclusion constraint, and hierarchy direction — not power-group membership.

See `seed-legal-rel-types.sql` for the seed data.

### Imported Roles

| Code | Name | `primary_influencer_only` | Notes |
|------|------|--------------------------|-------|
| HFOR | Hovedforetak (parent company) | TRUE | Always 1:1 |
| EIKM | Eierkommune (owner municipality) | TRUE | Always 1:1 |
| KOMP | Komplementar (general partner) | TRUE | Always 1:1 |
| DTPR | Deltaker pro-rata | FALSE | Proportional liability partner, can be many-to-one |
| DTSO | Deltaker solidarisk | FALSE | Joint liability partner, can be many-to-one |

### Excluded Roles

- **KENK** (Kontrollerende enhet): Duplicates HFOR
- **KDEB** (Komplementar/debitor): Duplicates KOMP

### Why Not Percentages?

BRREG does not provide ownership percentages. Fabricating percentages (e.g., 50% for partners) caused exclusion constraint violations when multiple partners shared ownership. The type-based approach (`primary_influencer_only`) accurately reflects what BRREG provides: HFOR/EIKM/KOMP are structurally guaranteed to be single-root relationships.

### Partnership Structures

Norwegian partnership forms (ANS, DA, KS) have multiple co-equal partners via DTPR/DTSO relationships. These DO form power groups today: the partners and the partnership cluster into one group, and a unit influenced by several partners is a multi-root case handled by `power_root` (`derived_root_status = 'multi'`). What DTPR/DTSO edges do NOT do is establish single-controller hierarchy — they are 1:N, outside the exclusion constraint, and carry no `primary` flag. How such non-controlling edges relate to the controlling (konsern) view is the subject of the power-group viewpoints design (STATBUS-179). See `doc/power-groups.md`.

## Pipeline Scripts

- `download-to-tmp.sh` — Downloads BRREG data files to `tmp/`
- `extract-roller-to-csv.py` — Extracts role relationships from BRREG JSON to CSV
- `brreg-import-downloads-from-tmp.sh` — Imports downloaded data into STATBUS
- `brreg-import-selection.sh` — Imports a selected subset
- `brreg-draw-samples.sh` / `.sql` — Draws random samples for testing
- `brreg-monthly.sh` — The monthly intake on rune (below)
- `brreg-fit-csv.py` — Fits a BRREG download to a definition's columns by name and derives legal unit status
- `brreg-deletions-since.py` — Reads BRREG's change feed and writes the units deleted since a date

## Monthly Intake

Norway (rune) takes in BRREG every month, unattended, from the statbus user's crontab (STATBUS-600). The run on the 2nd downloads the full files BRREG built on the 1st, which hold the register as of the end of the previous month, and closes the units that left the register. Jobs per month, in this order:

| Job | Definition | Rows | Valid from |
|-----|-----------|------|------------|
| `import_hovedenhet_YYYY_MM` | `brreg_hovedenhet_2025` | every legal unit | 1st of the month the file covers |
| `import_underenhet_YYYY_MM` | `brreg_underenhet_2025` | every establishment whose legal unit is in the file | same |
| `import_roller_YYYY_MM` | `brreg_roller_2025` | every controlling relationship between two legal units in the file | same |
| `import_hovedenhet_slettet_YYYY_MM` | `legal_unit_source_dates` | each legal unit that left the register | per row |
| `import_underenhet_slettet_YYYY_MM` | `establishment_for_lu_source_dates` | each establishment that left the register | per row |

`YYYY_MM` is the month the files cover: the run on 2 December creates `import_hovedenhet_2026_11`, valid from 1 November, so a unit born in November counts as a November birth. A full-file job adds a record only for a unit that changed; an unchanged unit keeps its record.

A closure row is `organisasjonsnummer`, `death_date`, and `valid_from` = the 1st of the month containing the day before the death, raised to the unit's first StatBus record, because the import requires the death to fall after the start of the record it writes. A unit BRREG's change feed reports as deleted closes on its `slettedato`. A unit StatBus still counts that the full file no longer lists, without a deletion in the feed, closes on its `slettedato` when the BRREG lookup has one, otherwise on the 1st of the run month, and is counted separately. The unit stops counting on its closing day; its history stays. Deletions for a unit StatBus never had (born and deleted between two runs) are counted, not imported. A closure job exists only when its list has rows.

Catch-up: `--deletions-only --since A --until B` replays one past month's deletions with their exact dates and creates no full-file job, because BRREG publishes only today's full file. A baseline loaded with its real snapshot date, followed by one catch-up run per month, exercises the monthly path without waiting months.

Status: BRREG has no status column, only flags. The loader derives `status_code` before upload: `passive` when `konkurs`, `underAvvikling` or `underTvangsavviklingEllerTvangsopplosning` is true, otherwise `active`. Establishments stay `active` until deleted. This bridge goes when import definitions can derive values themselves (STATBUS-601).

BRREG adds columns to its downloads over time, so the loader writes each file with exactly the definition's columns, matched by name.

Each run waits up to two hours for a scheduled or running upgrade, then skips the month and reports it. It stops at the first failure, posts it to `#statbus-utvikling`, and does not retry. The figures are the month's import jobs and StatBus's own history; the Slack message compares this run's jobs with the previous run's. Run state lives in `tmp/brreg-monthly/`: `last-since` (where the next run starts reading the feed), each run's files, and one log per run.

The crontab entry, as the statbus user on rune (02:00 Oslo time on the 2nd). The scripts run from their own clone (`~/brreg-monthly`, kept on master with `git pull`) so the release checkout `~/statbus`, which the upgrader manages, stays clean; `STATBUS_DIR` points them at it:

```
0 2 2 * * cd ~/statbus && git -C ~/brreg-monthly pull -q --ff-only; STATBUS_DIR=~/statbus USER_EMAIL=<owner email> SLACK_TOKEN=$(./sb dotenv -f .env get SLACK_TOKEN) ~/brreg-monthly/samples/norway/brreg/brreg-monthly.sh >> ~/statbus/tmp/brreg-monthly/cron.log 2>&1
```

Run one month by hand with `--month YYYY-MM`; `--dry-run` downloads, fits and counts without creating jobs.

## Import Definitions

- `create-import-definition-hovedenhet-*.sql` — Legal unit (hovedenhet) import definitions
- `create-import-definition-underenhet-*.sql` — Establishment (underenhet) import definitions
- `create-import-definition-roller-2025.sql` — Role/relationship (roller) import definition
