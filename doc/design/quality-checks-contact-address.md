# Quality checks: missing contact and address data

## Goal

Add three new quality checks to the Data quality section, following the same
pattern as `quality_establishment_activity_differs`:

1. **Missing email** — units where `email_address` is NULL or does not contain `@`
2. **Missing phone** — units where `phone_number`, `landline`, and `mobile_number` are all NULL or empty
3. **Missing postal address** — units where `postal_address_part1` is NULL or empty

Each check surfaces units with incomplete contact or address data so an operator
can prioritise data collection.

## Scope

These checks apply to **all unit types** (legal units, establishments, enterprises),
unlike `quality_establishment_activity_differs` which only applies to legal units.

## Pattern (from `quality_establishment_activity_differs`)

Each quality check has four database objects and four frontend components:

### Database (one migration per check)

| Object | Purpose |
|--------|---------|
| `public.quality_<check>` table | Holds one row per unit that fails the check. PK `(unit_type, unit_id, valid_range)`. NOT ENFORCED FK to `statistical_unit` for PostgREST embedding. |
| `public.quality_<check>_def` view | The rule: a SELECT that returns the rows belonging in the table. |
| `public.quality_<check>_derive()` function | MERGE from `_def` into the table. Called by `worker.derive_quality`. |
| `worker.derive_quality` procedure | Updated to call each new `_derive()`. Already calls the activity-differs check. |

Plus:
- `admin.add_rls_regular_user_can_read` on the new table
- `admin.apply_rls_to_all_tables` updated to include the new table
- `public.reset()` updated to TRUNCATE the new table alongside `statistical_unit`
- `worker.pipeline_step_weight` updated if the new checks are slow enough to matter

### Frontend (follows the existing filter pattern)

| Component | Purpose |
|-----------|---------|
| `app/src/app/search/filters/quality-<check>-filter.tsx` | Filter chip UI |
| `app/src/app/search/filters/url-search-params.ts` | URL param → PostgREST select mapping |
| `app/src/app/dashboard/quality-<check>-card.tsx` | Dashboard card with count + link to search |
| `app/src/app/search/export/export-sql.ts` | `SELECT_FILTERS` entry for SQL export |

## Check 1: `quality_missing_email`

### Definition view

```sql
CREATE VIEW public.quality_missing_email_def
WITH (security_invoker = on) AS
SELECT su.unit_type,
       su.unit_id,
       su.valid_from,
       su.valid_until,
       su.email_address
FROM public.statistical_unit AS su
WHERE su.email_address IS NULL
   OR su.email_address !~ '@';
```

### Table columns

- `unit_type`, `unit_id`, `valid_from`, `valid_until`, `valid_range` (generated)
- `email_address` — the value at the time (NULL or the invalid one)

### PostgREST usage

```
/rest/statistical_unit?select=*,quality_missing_email!inner()
```

## Check 2: `quality_missing_phone`

### Definition view

```sql
CREATE VIEW public.quality_missing_phone_def
WITH (security_invoker = on) AS
SELECT su.unit_type,
       su.unit_id,
       su.valid_from,
       su.valid_until,
       su.phone_number,
       su.landline,
       su.mobile_number
FROM public.statistical_unit AS su
WHERE COALESCE(su.phone_number, '') = ''
  AND COALESCE(su.landline, '') = ''
  AND COALESCE(su.mobile_number, '') = '';
```

### Table columns

- `unit_type`, `unit_id`, `valid_from`, `valid_until`, `valid_range` (generated)
- `phone_number`, `landline`, `mobile_number` — all NULL/empty

### PostgREST usage

```
/rest/statistical_unit?select=*,quality_missing_phone!inner()
```

## Check 3: `quality_missing_postal_address`

### Definition view

```sql
CREATE VIEW public.quality_missing_postal_address_def
WITH (security_invoker = on) AS
SELECT su.unit_type,
       su.unit_id,
       su.valid_from,
       su.valid_until,
       su.postal_address_part1
FROM public.statistical_unit AS su
WHERE COALESCE(su.postal_address_part1, '') = '';
```

### Table columns

- `unit_type`, `unit_id`, `valid_from`, `valid_until`, `valid_range` (generated)
- `postal_address_part1` — the empty/NULL value

### PostgREST usage

```
/rest/statistical_unit?select=*,quality_missing_postal_address!inner()
```

## Changes to existing code

### `worker.derive_quality` procedure

Add calls to the three new `_derive()` functions:

```sql
CREATE OR REPLACE PROCEDURE worker.derive_quality(...)
BEGIN
    PERFORM public.quality_establishment_activity_differs_derive();
    PERFORM public.quality_missing_email_derive();
    PERFORM public.quality_missing_phone_derive();
    PERFORM public.quality_missing_postal_address_derive();

    p_info := jsonb_build_object('checks', jsonb_build_array(
        'quality_establishment_activity_differs',
        'quality_missing_email',
        'quality_missing_phone',
        'quality_missing_postal_address'
    ));
END;
```

### `public.reset()`

Add the new tables to the TRUNCATE alongside `quality_establishment_activity_differs`:

```sql
TRUNCATE public.statistical_unit,
         public.quality_establishment_activity_differs,
         public.quality_missing_email,
         public.quality_missing_phone,
         public.quality_missing_postal_address
         CASCADE;
```

### `statistical_unit_refresh`

Same TRUNCATE update as `reset()`.

### `admin.apply_rls_to_all_tables()`

Add:
```sql
PERFORM admin.add_rls_regular_user_can_read('public.quality_missing_email'::regclass);
PERFORM admin.add_rls_regular_user_can_read('public.quality_missing_phone'::regclass);
PERFORM admin.add_rls_regular_user_can_read('public.quality_missing_postal_address'::regclass);
```

### Frontend search params (`url-search-params.ts`)

Add constants and state derivation for each new quality filter, following the
`primaryEstablishmentActivityDiffers` pattern.

### Frontend export SQL (`export-sql.ts`)

Add `SELECT_FILTERS` entries for each new quality embed select.

### Dashboard

Add cards for each check, showing count and linking to filtered search.

## Performance estimate

These checks are simpler than `quality_establishment_activity_differs` (no JOIN
to `timeline_establishment`, just column checks on `statistical_unit`). On the
Norway dataset (~2M rows) each MERGE should take 1–3 seconds. The combined
weight in `pipeline_step_weight` can stay at 1 (same as the existing check).

## Open questions for review

1. Should these checks apply to **all** unit types or only legal units?
   (Proposed: all, since contact data matters everywhere.)
2. Should we add a generic quality filter dropdown in the search bar that lists
   all available checks, rather than separate filter components?
3. Should missing email also flag obviously invalid formats beyond just the `@` check?
4. The dashboard already has a "Missing physical location" card. Units flagged
   by that check have no coordinates — this is exactly the set that cannot be
   placed on the statistical units map. Could the map link to this quality
   filter, or vice versa (e.g. a "Show on map" action from the quality list)?
