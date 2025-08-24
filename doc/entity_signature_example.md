# Example: The `entity_signature` Bug and Fix

This document provides a simplified example to illustrate the core bug in `analyse_external_idents` and how the fix corrects it.

## The Scenario

Consider an `establishment_formal` import with two rows representing the history of a single establishment (`EST_101`) that moves from one parent Legal Unit (`LU_A`) to another (`LU_B`).

**Source Data:**
| row_id | tax_ident (EST) | legal_unit_tax_ident (LU) | valid_from |
|--------|-----------------|---------------------------|------------|
| 1      | `900101`        | `800001`                  | 2023-01-01 |
| 2      | `900101`        | `800002`                  | 2024-01-01 |

The correct outcome is that `EST_101` is treated as a single entity whose history is being updated. This means `row_id = 1` should be an `insert` and `row_id = 2` should be a `replace`, and both should share the same `founding_row_id`.

---

## Old Behavior (Incorrect)

The old `analyse_external_idents` procedure did not correctly distinguish between an entity's own identifiers and its parent's identifiers.

1.  **Entity Signature Calculation:** It created the `entity_signature` (the unique key for a logical entity) by combining *all* available identifiers from the row.
    *   **Row 1 Signature:** `{"tax_ident": "900101", "legal_unit_tax_ident": "800001"}`
    *   **Row 2 Signature:** `{"tax_ident": "900101", "legal_unit_tax_ident": "800002"}`

2.  **Analysis Result:** Because the signatures were different, the procedure incorrectly concluded that these were two separate new entities.
    *   **Row 1:** `operation = 'insert'`, `action = 'insert'`, `founding_row_id = 1`
    *   **Row 2:** `operation = 'insert'`, `action = 'insert'`, `founding_row_id = 2`

3.  **Downstream Failure:** This incorrect analysis is the root cause of all test failures. The processing phase receives two `insert` actions for the same establishment, leading to data corruption and dependency errors.

---

## New Behavior (Correct)

The fixed `analyse_external_idents` procedure is now mode-aware.

1.  **Entity Signature Calculation:** When the import `mode` is `establishment_formal`, it knows to build the `entity_signature` using **only** the establishment's own identifiers. It correctly identifies `legal_unit_tax_ident` as a parent identifier (by parsing the `legal_unit_` prefix from the column name) and excludes it from the signature.
    *   **Row 1 Signature:** `{"tax_ident": "900101"}`
    *   **Row 2 Signature:** `{"tax_ident": "900101"}`

2.  **Analysis Result:** Because the signatures are now identical, the procedure correctly identifies the two rows as historical slices of the same logical entity.
    *   **Row 1 (2023):** `operation = 'insert'`, `action = 'insert'`, `founding_row_id = 1`
    *   **Row 2 (2024):** `operation = 'replace'`, `action = 'replace'`, `founding_row_id = 1`

3.  **Downstream Success:** The processing phase receives the correct sequence of `insert` and `replace` actions with a shared `founding_row_id`, allowing it to build the full, correct history for the establishment.
