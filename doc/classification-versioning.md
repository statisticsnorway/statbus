# Classification Versioning

## Overview

Classification tables in STATBUS (region, activity_category_standard, etc.) represent code systems that change over time. Norway's region codes were reformed in 2020 then partially reversed in 2024. ISIC/NACE standards get revised periodically. Without versioning, uploading new classifications breaks FK constraints and path uniqueness.

## Version Tables

### `region_version`

Each region version represents a complete set of region codes (e.g., "Norway 2020", "Norway 2024").

```sql
CREATE TABLE public.region_version (
    id INTEGER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    code TEXT UNIQUE NOT NULL,           -- 'v2020', 'v2024'
    name TEXT NOT NULL,
    description TEXT,
    lasts_to DATE,                       -- Inclusive end date. NULL = currently active.
    enabled BOOLEAN NOT NULL DEFAULT true,
    custom BOOLEAN NOT NULL DEFAULT false
);
```

### `activity_category_standard`

Already existed. Added `lasts_to` column for forward compatibility:

```sql
ALTER TABLE activity_category_standard ADD COLUMN lasts_to DATE;
```

Unlike `region_version`, multiple activity category standards can be "current" simultaneously (e.g., ISIC v4 and NACE v2.1), so there is no uniqueness constraint on `lasts_to`.

### Timeline Integrity

For `region_version`, a UNIQUE partial index ensures only one enabled version can be "current" (NULL `lasts_to`):

```sql
CREATE UNIQUE INDEX region_version_enabled_lasts_to_key
    ON region_version (lasts_to) NULLS NOT DISTINCT WHERE enabled;
```

This allows:
- One active version (lasts_to IS NULL, enabled)
- Multiple past versions (lasts_to = some date, enabled)
- Disabled versions (enabled = false, any lasts_to)

## Dual Foreign Keys

### Region → Location

`location` has both `region_id` and `region_version_id`. A dual FK ensures consistency:

```sql
ALTER TABLE location ADD CONSTRAINT location_region_dual_fk
    FOREIGN KEY (region_id, region_version_id) REFERENCES region(id, version_id);
```

This means a location always points to a region within a specific version — you can't accidentally link to a region from the wrong version.

### Settings → Enabled Versions

Settings must point to enabled versions only. A GENERATED column enforces this:

```sql
ALTER TABLE settings ADD COLUMN required_to_be_enabled BOOLEAN
    GENERATED ALWAYS AS (true) STORED;

ALTER TABLE settings ADD CONSTRAINT settings_region_version_enabled_fk
    FOREIGN KEY (region_version_id, required_to_be_enabled)
    REFERENCES region_version(id, enabled);
```

This works because `required_to_be_enabled` is always `true`, and the FK requires `region_version.enabled = true`. If you disable a version that settings points to, the FK fails.

Same pattern for `activity_category_standard`:

```sql
ALTER TABLE settings ADD CONSTRAINT settings_activity_category_standard_enabled_fk
    FOREIGN KEY (activity_category_standard_id, required_to_be_enabled)
    REFERENCES activity_category_standard(id, enabled);
```

## Gradual Migration

Version transitions don't require a big-bang switchover:

1. **Upload new version**: Insert new `region_version`, upload regions with that `version_id`
2. **Assign new regions**: Update `location.region_id` and `location.region_version_id` for units that have deterministic mappings
3. **Query completeness**: Find locations still on the old version
4. **Switch settings**: Update `settings.region_version_id` when ready
5. **Disable old version**: Set `enabled = false` on the old version

Because `location` is temporal, you can assign new-version regions for future periods while keeping old-version regions for historical periods.

## Change Tracking

Region metadata changes (name, coordinates) trigger the worker pipeline via `worker.log_region_change()`. This function JOINs through `location` to find affected establishments and legal units, writing to `worker.base_change_log` like all other base-data triggers.

## Future: Upgrade Mapping

For automated version transitions, upgrade mapping tables would track how codes map between versions:

```sql
-- Future: region_upgrade table
CREATE TABLE region_upgrade (
    id INTEGER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    from_version_id INTEGER NOT NULL REFERENCES region_version(id),
    to_version_id INTEGER NOT NULL REFERENCES region_version(id),
    from_region_id INTEGER NOT NULL REFERENCES region(id),
    to_region_id INTEGER NOT NULL REFERENCES region(id),
    split_weight NUMERIC(5,4),  -- For splits: 0.5 = ambiguous, 1.0 = deterministic
    UNIQUE (from_version_id, to_version_id, from_region_id, to_region_id)
);
```

**Deterministic mappings** (`split_weight = 1.0`): One old code → one new code. Can be auto-applied.

**Non-deterministic mappings** (`split_weight < 1.0`): One old code → multiple new codes (splits). Requires manual assignment or heuristics.

## Cross-Version Aggregation

For historical drill-down across version boundaries, use shared ancestor paths. If two versions share a common parent hierarchy (e.g., county level unchanged), aggregation can use the lowest common ancestor path that exists in both versions.
