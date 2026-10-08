# Text length bounds

Where STATBUS bounds the length of a text column, the bound is a deliberate,
documented number backed by measured data, and a value above it fails
honestly rather than being truncated. This document records each such
decision and its evidence. It starts with `activity_category.name`, the first
bound decided this way (STATBUS-472); add a section here whenever another
bound is chosen or moved.

## What a bound costs in PostgreSQL

`character varying(n)` is a length check, not a storage layout. A value is
stored with exactly its own length whatever `n` is, so raising `n` changes no
row size, page layout or index size, and widening it is a catalog change with
no table rewrite. The only thing `n` buys is the check itself: an insert or
update longer than `n` fails with SQLSTATE `22001`
(`value too long for type character varying(n)`), the whole statement is
rejected, and nothing is silently cut short. That honest failure is the point
of keeping a bound at all instead of `text`.

## `activity_category.name`: 512 characters

| | |
|---|---|
| Column | `public.activity_category.name character varying(512) NOT NULL` |
| Previous bound | 256 (from the original 2024 table) |
| Decided | 2026-10-08, STATBUS-472 (owner decision) |
| Migration | `migrations/20261008132050_statbus_472_activity_category_name_bound_512` |
| Test | `test/sql/132_statbus_472_activity_category_name_bound_512.sql` |
| Above the bound | the upload fails with SQLSTATE 22001, nothing is stored |

### Evidence

Measured on 2026-10-08:

| Source | Rows | Longest name | Mean |
|---|---:|---:|---:|
| ISIC Rev. 4, shipped standard (`isic_v4`) | 766 | 136 | 42.1 |
| NACE Rev. 2.1, shipped standard (`nace_v2.1`) | 1,047 | 139 | 43.6 |
| Field file `ClassificationsSBVer2_ActivityCategoris_TCC.csv` (custom upload, Turkish `---` English) | 997 | 252 | 92.9 |

The field file's longest label (section `T`) is 252 characters only because
the operator had already hand-trimmed it to squeeze under 256: the English
half ends in `services...for own use`. Untrimmed, the Turkish label (158) plus
the separator plus the official English label (122) is 285 characters. A
single-language official label never comes close to either bound; it is
combining languages in one name that pushes past 256.

### Why 512

Doubling the bound lets every label in the field file, including its
untrimmed forms, import unedited, with headroom for a third language or a
longer local label. It costs nothing in storage (see above). It is an interim
workaround: proper multi-language category names (one name per language, a
custom local name overriding the official English name of the same path) are
designed but deferred, and that discussion is kept in the notes of
STATBUS-472. Until then, how an operator combines several languages within
one name is their choice, within 512 characters.

The bound stays a bound: it is not raised further and not replaced by
`text`, so a runaway value (a whole description pasted into the name column,
a broken CSV quote swallowing many fields) is still rejected with an
actionable error instead of being stored.

### Where the bound applies

The column type flows to everything that exposes it, and all of these report
`character varying(512)`:

- the table `public.activity_category`;
- the views `activity_category_enabled`, `activity_category_enabled_custom`
  (the custom CSV upload target), `activity_category_isic_v4`,
  `activity_category_nace_v2_1` (the standard loaders) and
  `activity_category_used_def`;
- the derived table `public.activity_category_used`, which is filled from
  `activity_category_used_def` by `activity_category_used_derive()` and so
  must carry the same bound or it would reject a long label at derive time.

The upsert trigger functions behind those views
(`admin.upsert_activity_category`, `admin.activity_category_enabled_upsert_custom`,
`admin.activity_category_enabled_custom_upsert_custom`) and
`public.activity_category_used_derive` copy the name through without any cast,
so they need no change. `timeline_establishment_def` and
`timeline_legal_unit_def` read `activity_category` but not its name.

## Other bounded text columns

These still carry their original 2024 bound of 256 and have not been
measured or decided under this policy: `legal_unit.name`,
`establishment.name`, `enterprise_group.name`, `power_group.name`,
`tag.name`, `contact.web_address`, `relative_period.name_when_query` and
`relative_period.name_when_input` (and the timeline, statistical_unit and
view columns derived from them). When one of them needs to move, measure the
real data, decide, and record it here.
