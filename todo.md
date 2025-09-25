# Done
- Fixed a state corruption bug in `import_job_processing_phase` where `error` states could be incorrectly overwritten with `processed`.
- All import procedures for sub-entities now use the modern pattern (passing natural keys to `temporal_merge`) following an upstream bug fix in `sql_saga`.
- Fixed a persistent "duplicate key" violation in `analyse_external_idents` by correcting a faulty JOIN condition that was causing data fan-out when joining to temporal tables.

# Todo
- [x] **Refactor: Standardize JSONB `errors`, `invalid_codes`, and `merge_status` columns**
  - **Problem**: The `errors`, `invalid_codes`, and `merge_status` JSONB columns in `import_*_data` tables are nullable. The procedures are inconsistent in treating `NULL` vs an empty object (`'{}'`) as "no errors".
  - **Solution**: Standardize on `'{}'` as the representation for "no errors" and enforce this at the database level.
  - **Plan**:
    1.  [x] **Create Migration**: The `import_job_generate` function now correctly creates these columns as `NOT NULL DEFAULT '{}'::jsonb`. Procedures are being updated to remove redundant `COALESCE` calls.

- [ ] **Refactor: Add `_path` columns for code lookups**: The import system's `analyse_*` procedures currently only look up codes (e.g., `sector_code`) by their simple code value. To properly support hierarchical code lists (like `sector`), a parallel `_path` column (e.g., `sector_path`) should be added to the `import_data_column` definitions for each code list. The `analyse_*` procedures should then be updated to intelligently choose the lookup method: if a `_path` column is present and has a value, it should be used to look up against the `path` column; otherwise, the `_code` column should be used to look up against the `code` column.

- [ ] **Design Review**
  - The `tag` table (`migrations/20240116000000_create_table_tag.up.sql`) was skipped during the temporal upgrade pending a design review of its custom date logic.

- [ ] **DevOps: Document and standardize query plan generation in tests**
  - **Problem**: Query plans can change unexpectedly. `EXPLAIN ANALYZE` is not test-stable.
  - **Solution**: A pattern has been established in test `303` to use `EXPLAIN` (without `ANALYZE`) and save the output to `test/expected/`. This makes plan changes visible in `git diff`.
  - **Plan**:
    1. [ ] Document this convention in `CONVENTIONS.md`.
    2. [ ] Apply this pattern to other key integration tests.

- [ ] **Refactor: Use GIST indexes in timeline views**
  - **Problem**: The `timeline_legal_unit_def` and `timeline_establishment_def` views are not using GIST indexes for temporal subqueries, leading to slow sequential scans.
  - **Solution**: Refactor the subqueries in these views to use `daterange` types and the `&&` (overlaps) operator to enable index usage.
  - **Plan**:
    1. [ ] Locate the migration files that define these views.
    2. [ ] Refactor the subqueries for `activity`, `location`, `contact`, and `stat_for_unit` to use `daterange` operators.
    3. [ ] Verify the query plans are updated to use Index Scans.

