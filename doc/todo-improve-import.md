# Todo for new import system

### Future Consideration: 'Update' Strategy

The current `replace` action, particularly when used with temporal data via `batch_insert_or_replace_generic_valid_time_table`, effectively replaces the entire data slice for the overlapping validity period. There's a need for a more granular 'update' capability.

An 'update' strategy/operation/action would be beneficial for:
*   Updating non-temporal tables where a full replace is unnecessary.
*   Modifying specific fields of an existing temporal record *without altering its `valid_from` or `valid_to` dates*. This is useful for correcting data like a name typo or changing a contact detail that doesn't have its own temporal history managed by the batch function.

This would involve:
*   Adding an 'update' value to `public.import_strategy`, `public.import_row_operation_type`, and `public.import_row_action_type`.
*   The `analyse_external_idents` procedure would need to determine if an 'update' operation is appropriate (e.g., existing unit found, and strategy allows for update).
*   The `process_*` procedures would then execute direct SQL `UPDATE` statements for rows with `action = 'update'`, targeting specific columns and preserving existing `valid_from`/`valid_to` for temporal records.

## Implement 'update' strategy for non-temporal data and partial temporal updates

*   **Extend Enum Types:**
    *   Add 'update' to `public.import_strategy`.
    *   Add 'update' to `public.import_row_operation_type`.
    *   Add 'update' to `public.import_row_action_type`.
*   **Modify `analyse_external_idents`:**
    *   Update logic to correctly determine `operation = 'update'` (e.g., if unit exists and strategy is `update_only` or `insert_or_update` or `insert_or_replace_or_update`).
    *   Update logic to correctly determine `action = 'update'` based on the new `operation` and `strategy` combinations.
*   **Modify `process_*` Procedures:**
    *   For relevant steps, add logic to handle `action = 'update'`.
    *   This will typically involve constructing and executing direct SQL `UPDATE` statements on the target tables.
    *   For temporal tables, ensure these `UPDATE` statements modify only non-temporal fields or fields not involved in the `batch_insert_or_replace` logic, and *do not* alter `valid_from` / `valid_to` unless specifically intended by a new type of batch function.
*   **Update Documentation:**
    *   Reflect the new 'update' strategy, operation, and action in `doc/import-system.md`.
    *   Document how `process_*` procedures should handle `action = 'update'`.
*   **Update Tests:**
    *   Add new tests to verify the 'update' strategy for both non-temporal and temporal data scenarios.
