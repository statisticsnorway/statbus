## 6. Future Work: Generalization as `sql_saga.temporal_merge`

This section outlines the definitive proposal for integrating the set-based temporal logic into the `sql_saga` extension as a single, powerful, and semantically clear procedure.

### 6.1. Vision and Semantic Clarity

The goal is to provide a function that feels like a native PostgreSQL command, analogous to `MERGE`, but designed specifically for temporal tables. The key to this is making the caller's intent explicit through a `mode` parameter. This avoids ambiguity and provides clear, predictable behavior for different use cases like data import, user-driven edits, and append-only streams.

The naming and behavior are designed to align with concepts from the SQL standard:
-   Modes that modify data within existing timelines (e.g., `'patch_only'`) are directly equivalent to a set-based `UPDATE ... FOR PORTION OF`.
-   The overall function acts as a temporal `MERGE`, handling `INSERT`, `UPDATE`, and `DELETE` operations on a timeline based on the specified mode.

### 6.2. Proposed Unified API

A single procedure, `sql_saga.temporal_merge`, will provide all functionality.

#### 6.2.1. The `mode` ENUM: Defining Intent

The core of the API is a new `ENUM` that precisely defines the operation's behavior using clear, intuitive terms.

```sql
CREATE TYPE sql_saga.temporal_merge_mode AS ENUM (
    'upsert_patch',
    'upsert_replace',
    'patch_only',
    'replace_only',
    'insert_only'
);
```

**Semantic Definitions:**

| Mode | Use Case | If Entity Exists... | If Entity Doesn't Exist... | `NULL`s in Source Data... |
| :--- | :--- | :--- | :--- | :--- |
| **`upsert_patch`** | Standard Import | **Patches** timeline, preserving non-overlapping history. | **Inserts** new timeline. | Are **ignored** (existing values preserved). |
| **`upsert_replace`** | Idempotent Import | **Replaces** timeline portions, preserving non-overlapping history. | **Inserts** new timeline. | **Overwrite** existing values. |
| **`patch_only`** | User Edits | **Patches** timeline, preserving non-overlapping history. | Is a **NOOP**. | Are **ignored**. |
| **`replace_only`** | Data Correction | **Replaces** timeline portions, preserving non-overlapping history. | Is a **NOOP**. | **Overwrite** existing values. |
| **`insert_only`** | Append-Only Data | Is a **NOOP**. | **Inserts** new timeline. | N/A (always inserts). |

#### 6.2.2. Procedure Signature

```sql
PROCEDURE sql_saga.temporal_merge(
    p_target_table regclass,
    p_source_table regclass,
    p_id_columns text[],
    p_mode sql_saga.temporal_merge_mode,
    p_ephemeral_columns text[] DEFAULT '{}',
    p_exclude_from_insert text[] DEFAULT '{}'
);
```

#### 6.2.3. Parameters
*   `p_target_table regclass`: The target temporal table.
*   `p_source_table regclass`: The source table/view with new data.
*   `p_id_columns text[]`: Array of column names forming the conceptual primary key.
*   `p_mode sql_saga.temporal_merge_mode`: The operational mode, as defined above.
*   `p_ephemeral_columns text[]`: Columns to exclude from data-equivalence checks (e.g., audit columns).
*   `p_exclude_from_insert text[]`: Columns with database `DEFAULT` values (like surrogate keys) to exclude from `INSERT` statements.

### 6.3. Implementation and Generalization Notes

*   **Introspection**: The procedure will use `information_schema` to discover common data columns, ensuring it is robust and not reliant on strict naming conventions.
*   **Result Reporting**: For a general-purpose `sql_saga` procedure, row-level feedback is not required. The procedure will succeed or fail atomically for the entire batch, which is simpler and aligns with standard DML commands. The Statbus-specific `temporal_merge` orchestrator function (which returns a `SETOF` records) will remain as a wrapper that calls this procedure and then generates the detailed row-level feedback required by the import job system.
*   **Source Row Identification**: The shift to a `PROCEDURE` with batch-level feedback means the generic function no longer needs to know about a `row_id` column, making it truly general-purpose.

This refined proposal provides a clear and powerful vision for extending `sql_saga` and serves as the definitive guide for finalizing the implementation within the Statbus project.
