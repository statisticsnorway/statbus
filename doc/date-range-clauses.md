## Date Range Operations

### OVERLAPS vs daterange

PostgreSQL provides two main ways to check if date ranges overlap:

1. **OVERLAPS operator**: `(start1, end1) OVERLAPS (start2, end2)`
2. **Range operator**: `daterange(start1, end1, bounds) && daterange(start2, end2, bounds)`

The key difference is how boundaries are handled:

- **OVERLAPS** implicitly uses inclusive-inclusive `[]` boundaries
- **daterange** allows explicit boundary specification:
  - `[]`: inclusive-inclusive (default)
  - `[)`: inclusive-exclusive
  - `(]`: exclusive-inclusive
  - `()`: exclusive-exclusive

### Naming Convention Impact

When using column names like:
- `valid_from`: Implies an inclusive lower bound (the range starts AT this date)
- `valid_after`: Implies an exclusive lower bound (the range starts AFTER this date)

Therefore:
- `(valid_from, valid_to) OVERLAPS (...)` is equivalent to `daterange(valid_from, valid_to, '[]') && daterange(...)`
- `(valid_after, valid_to) OVERLAPS (...)` is logically equivalent to `daterange(valid_after, valid_to, '(]') && daterange(...)`

This naming convention helps clarify the intended boundary behavior in the database schema.

#### Example: Starting from January 1, 2023

If you want a range that starts from January 1, 2023 (inclusive):
- Using `valid_from`: Set `valid_from = '2023-01-01'`
- Using `valid_after`: Set `valid_after = '2022-12-31'` (the day before)

This is because:
- `valid_from = '2023-01-01'` means "valid starting on January 1, 2023"
- `valid_after = '2022-12-31'` means "valid after December 31, 2022" (which is the same as "from January 1, 2023")

### Performance Considerations

When choosing between OVERLAPS and daterange operators, consider these performance factors:

1. **Query Optimizer Behavior**: 
   - The PostgreSQL optimizer may handle OVERLAPS and daterange differently
   - OVERLAPS is a built-in operator that may have specific optimizations
   - daterange with && uses the GiST index infrastructure

2. **Infinity Handling**:
   - Special care is needed when using `-infinity` and `infinity` values
   - Comparisons like `valid_after < '-infinity'` will always be false
   - Using COALESCE or explicit equality checks can help handle edge cases

3. **Indexing Strategy**:
   - For daterange queries, consider creating a GiST index on the range: `CREATE INDEX ON table USING GIST (daterange(valid_after, valid_to, '(]'))`
   - For OVERLAPS queries, consider indexes on the individual columns

4. **Boundary Type Impact**:
   - The choice of boundary type ('[]', '(]', '[)', '()') affects both correctness and performance
   - Match the boundary type to your column naming convention for clarity

The performance tests in speed.sql provide empirical data on which approach performs better for specific query patterns in this database.
