# Architecture and Data Flow: `temporal_merge`

## 1. Introduction

This document clarifies the end-to-end data flow for the import system, focusing on the new, unified `temporal_merge` function. Its purpose is to explain the layers of abstraction, the flow of data, and the specific patterns used to resolve critical issues like intra-batch dependencies.

## 2. The Big Picture: Layers of Abstraction

The import system is designed as a series of layers, each with a distinct responsibility. This separates high-level job management from low-level data manipulation.

```text
+--------------------------------+
|      Import Job (Worker)       |  <-- Manages overall job state (e.g., 'processing')
+--------------------------------+
               |
               v
+--------------------------------+
|  `import_job_processing_phase` |  <-- Selects batches of rows and calls the correct step
+--------------------------------+
               |
               v
+--------------------------------+
|   `process_*` Procedures       |  <-- Business logic for one entity type (e.g., `process_legal_unit`)
| (e.g., `process_legal_unit`)   |      **Handles intra-batch dependencies.**
+--------------------------------+
               |
               v
+--------------------------------+
| `temporal_merge` Orchestrator  |  <-- Executes a temporal merge, calling the planner with a specific `mode`.
+--------------------------------+
               |
               v
+--------------------------------+
|  `temporal_merge_plan` Planner |  <-- Pure calculation engine for temporal logic
+--------------------------------+
```

## 3. The Core Challenge: Intra-Batch Dependencies

The most complex problem in the processing phase is handling dependencies between rows *within the same batch*.

**The Scenario:** A single batch for `process_legal_unit` contains multiple rows for the same **new** legal unit that doesn't exist in the database yet:
-   **Row 1**: The first historical record (`action=insert`). It needs to create a new `legal_unit` and get its database ID.
-   **Row 2**: A subsequent historical record (`action=replace`). It **depends on** the database ID from Row 1 to correctly update the timeline.

**The Question:** Who is responsible for resolving this dependency?

**The Answer & Design Philosophy:** The `process_*` procedure is responsible. This is a deliberate design choice based on the principle of **separation of concerns**:
-   **`temporal_merge` is a generic, "dumb" tool.** Its only job is to correctly merge a set of changes into a target table's timeline based on Allen's Interval Algebra. It has no knowledge of business logic, such as how rows in a source file relate to each other (e.g., via a `founding_row_id`). Keeping it generic makes it highly reusable and easier to test in isolation.
-   **`process_*` procedures contain business-specific logic.** A procedure like `process_legal_unit` understands the concept of a "new legal unit's history". It knows how to identify the founding record, create the entity, and propagate its new ID to related historical records.

This separation prevents `temporal_merge` from becoming bloated with special cases and keeps the business logic encapsulated where it belongs.

## 4. The Solution: The Two-Stage `process_*` Pattern

To solve the dependency problem, every `process_*` procedure that handles entity creation and updates within a batch **must** follow a specific two-stage pattern within a single transaction. This pattern leverages the explicit `mode` parameter of `temporal_merge` to ensure correctness and prevent race conditions or duplicate entities.

For a detailed, row-by-row walkthrough, see [Advanced Data Flow: Intra-Batch Dependencies and the Two-Stage Process](./temporal_merge_complex_flow_example.md).

The pattern is as follows:

1.  **Stage 1: Create New Entities (`upsert_*` mode)**
    -   The procedure first isolates and processes all rows with an `action` of `insert`.
    -   It calls `temporal_merge` for these rows using an `upsert_*` mode (e.g., `'upsert_replace'`). This mode instructs the function to create the entity if it doesn't exist.
    -   The function executes, creates the new database records, and returns their stable, generated IDs.

2.  **ID Propagation (The "Stitch")**
    -   The procedure takes the newly generated IDs from Stage 1.
    -   It updates the job's `_data` table, back-filling the new ID into **all other rows in the batch** that refer to the same conceptual entity (e.g., matching on `founding_row_id`). This crucial step "stitches" the entire history of the new entity to its stable database ID.

3.  **Stage 2: Update Existing Timelines (`*_only` mode)**
    -   The procedure then processes the remaining rows (e.g., `action = 'replace'`). All these rows now have the correct database ID.
    -   It calls `temporal_merge` a second time for this set of rows, but critically, it uses a `*_only` mode (e.g., `'replace_only'`).
    -   This mode provides a vital safety guarantee: it tells `temporal_merge` to *only* modify timelines for entities that **already exist**. If an ID was missing for any reason, the function would return `MISSING_TARGET` instead of accidentally creating a duplicate entity.

This explicit, two-stage process makes the dependency resolution robust, safe, and easy to reason about, removing the need for more complex mechanisms like a "batch fence." The importance of this specific execution order is demonstrated in the test suite (see `Scenario 35` in `015_test_temporal_merge.sql`).

## 5. The Role of `mode` and Complete Feedback

The two-stage pattern relies on two key features of the `temporal_merge` function:

-   **Explicit `mode`**: The `mode` parameter is not just a hint; it's a contract that defines the function's behavior. Using `upsert_*` and then `*_only` is what makes the two-stage pattern safe.
-   **Complete Feedback**: The `temporal_merge` function provides a result status for *every* source row passed to it. This is critical when the planner merges multiple source rows into a single database operation (e.g., extending a time slice). The orchestrator unnests the merged source row IDs and reports `SUCCESS` for all of them, ensuring the calling `process_*` procedure knows that every row has been handled.

## 6. Alternative Design Considered: A "Smarter" `temporal_merge`

A reasonable question is: why not make `temporal_merge` itself handle the two-stage process? Since the pattern of creating a new entity and then updating its timeline is repeated in every `process_*` procedure, moving this logic into the generic function seems like it would reduce boilerplate and simplify the callers.

If the function were to handle this, it would need to be given the business-specific context it currently lacks. Its API would need to be extended with parameters to describe the source data's dependency structure. The new API would look something like this:

```sql
FUNCTION import.temporal_merge(
    -- Core parameters (unchanged)
    p_target_schema_name TEXT,
    p_target_table_name TEXT,
    p_source_schema_name TEXT,
    p_source_table_name TEXT,
    p_entity_id_column_names TEXT[],
    p_source_row_ids INTEGER[],
    p_ephemeral_columns TEXT[],
    p_insert_defaulted_columns TEXT[],
    p_mode import.set_operation_mode,

    -- Parameters for "smart" dependency resolution
    p_source_row_id_column TEXT DEFAULT 'row_id',
    p_source_conceptual_key_column TEXT DEFAULT 'founding_row_id',
    p_source_action_column TEXT DEFAULT 'action'
)
```

The function's internal logic would become far more complex. It would have to:
1.  Identify new entities by finding rows within the `p_source_row_ids` batch where the `p_entity_id_column_names` are `NULL`.
2.  For these new entities, partition them into groups based on the `p_source_conceptual_key_column` (e.g., `founding_row_id`).
3.  Within each group, find the row with an `'insert'` action in the `p_source_action_column`.
4.  Execute a merge for just that `insert` row to get the new database ID.
5.  **Execute an `UPDATE` statement back against the source table** to propagate the new ID to all other rows in that group. This breaks the function's current model of treating the source as a read-only input.
6.  Execute a second merge for the remaining (`replace`) rows in the group, which now have the correct ID.
7.  Process all other source rows that had a non-null entity ID from the start.
8.  Combine all results.

While this would simplify the `process_*` procedures, it was rejected for several key reasons:
-   **Breaks Separation of Concerns**: It moves significant business-specific logic into a generic, low-level tool. The tool would become tightly coupled to the import system's specific schema (`action`, `founding_row_id`).
-   **Reduced Reusability**: The function would no longer be a pure, generic temporal merge utility that could be easily used in other contexts or with different data structures.
-   **Increased Complexity & "Magic"**: The internal logic of `temporal_merge` would be much harder to understand, test, and debug. The "stitching" process happening implicitly inside the function would feel like "magic," violating the principle of declarative transparency.

The current design, while requiring a bit more boilerplate in the callers, maintains a clean separation. `temporal_merge` remains a powerful but "dumb" and highly predictable tool, while the `process_*` procedures explicitly and clearly orchestrate the business logic required for the import.

## 7. Naming Conventions and Intent: The Ambiguity of `apply_`

The prefix `apply_` is often used to signal a mutating operation—a procedure or method that applies a change to a system's state. This is a reasonable and common convention in imperative programming. For example, `CALL import.apply_changes(..)` clearly suggests that changes will be applied to the database.

A fair question is: "Why would a function named `apply_` not have a mutating expectation?" This highlights a critical ambiguity, especially with PostgreSQL functions versus procedures.

-   **Procedures (`CALL my_proc()`)**: Procedures in PostgreSQL do not have a return value. Their *only* purpose is to perform actions, which almost always means producing side effects (mutating state). Therefore, a name like `execute_temporal_batch` for a procedure is perfectly aligned with expectations.

-   **Functions (`SELECT my_func()`)**: Functions are expected to return a value and, ideally, should not have side effects (i.e., they should be `STABLE` or `IMMUTABLE`). A function named `get_plan()` would be expected to return a plan without changing anything. However, PostgreSQL allows `VOLATILE` functions, which can both return a value and have side effects.

This is where the ambiguity arises. A function named `apply_temporal_merge` that also returns a result set is sending mixed signals. Does it *apply* the changes and return a log, or does it calculate what would be applied and return a plan?

In this system's design, we've consciously highlighted this as a significant drawback for any abstraction that uses a `VOLATILE` function with side effects (see Options 2 and 4 below). While such a function *could* be named `apply_...` to signal its mutating behavior, it violates the "Principle of Least Surprise" because developers are conditioned to expect functions to be non-mutating. This is why the procedure-based approach (Option 1) is recommended: it provides an unambiguous, imperative API where an `execute_` prefix aligns perfectly with the expected behavior.

## 8. Future Directions: A Higher-Level Abstraction

While the two-stage pattern is robust, its repetition in every `process_*` procedure represents boilerplate that could be eliminated. The natural next step is to introduce a new, higher-level abstraction that encapsulates this dependency resolution logic. This would simplify the `process_*` procedures, reducing them to a single call to this new layer.

Here are three potential designs for such an abstraction, with their respective trade-offs.

### Option 1: The Orchestrator Procedure (Recommended)

-   **Name**: `import.execute_temporal_batch`
-   **Feasibility**: High. This is the most direct and idiomatic approach in PL/pgSQL.
-   **Implementation**: A `PROCEDURE` that takes the job's `_data` table name and the batch of `row_id`s as input, along with parameters specifying the names of the `action` and `founding_row_id` columns.
    1.  It creates a temporary table to store results.
    2.  Internally, it performs the exact two-stage logic:
        a. Selects rows with `action = 'insert'`.
        b. Calls `temporal_merge` with `'upsert_replace'`.
        c. Captures the returned IDs and `UPDATE`s the `_data` table to propagate them based on `founding_row_id`.
        d. Selects the remaining rows (`action = 'replace'`).
        e. Calls `temporal_merge` again with `'replace_only'`.
    3.  It aggregates results from both calls and writes them to the results temporary table for the caller to inspect.
-   **Pros**:
    -   **Clean Separation**: Keeps the "smart" business logic separate from the "dumb" `temporal_merge` tool.
    -   **Reduces Boilerplate**: The `process_*` procedures become extremely simple.
    -   **Clear and Explicit**: The logic is imperative and easy to follow within the procedure body.
-   **Cons**:
    -   **Initial Setup Verbosity**: The caller is responsible for creating the temporary results table before calling the procedure.
-   **Design Rationale: Result Handling via Temporary Table**
    -   The procedure's API for returning results—by populating a temporary table created by the caller—is a deliberate design choice over using an `OUT` parameter.
    -   An `OUT` parameter would return an array of a composite type (e.g., `import.temporal_merge_result[]`). While this works for simple cases, querying this data structure within the calling PL/pgSQL code is cumbersome. It requires `UNNEST` and can make subsequent joins or complex analysis difficult without resorting to dynamic SQL.
    -   By passing in a temporary table name, the procedure gives the caller maximum control. The results are returned in a standard relational format that is immediately queryable. The caller can index this table, join it with other tables, and perform complex post-processing steps with simple, static SQL. This robust and flexible pattern is well-suited for complex data processing workflows, and the minor initial setup cost is outweighed by the downstream benefits.

### Option 2: The "Smarter" Wrapper Function

-   **Name**: `import.resolve_and_merge_batch`
-   **Feasibility**: Medium. This is functionally similar to Option 1 but implemented as a `VOLATILE` function.
-   **Implementation**: A function that `RETURNS TABLE(...)` with the results. It would take the same arguments as the procedure in Option 1. Critically, it would need to perform an `UPDATE` on the source `_data` table as a side effect to propagate the newly created entity IDs between the two internal calls to `temporal_merge`.
-   **Pros**:
    -   **Ergonomic API**: A function that returns a table is easier to call and integrate into queries than a procedure that requires a temporary table.
-   **Cons**:
    -   **Violates Principle of Least Surprise**: A function that modifies its input table (`_data`) as a side effect is non-obvious and can lead to confusion. This makes the system harder to reason about.
    -   **"Magic"**: Hides the critical `UPDATE` step, making the process less transparent.

### Option 3: The `INSTEAD OF` Trigger on a View

-   **Name**: `import.v_apply_temporal_batch` (a view)
-   **Feasibility**: Low. This is a highly declarative but complex and likely impractical approach.
-   **Implementation**: A generic view would be created. A `process_*` procedure would `INSERT` the batch of data into this view. An `INSTEAD OF INSERT` trigger on the view would fire, and its trigger function would contain the two-stage logic, operating on the `INSERTED` pseudo-table.
-   **Pros**:
    -   **Declarative API**: The call site is a simple, elegant `INSERT` statement.
-   **Cons**:
    -   **Extreme Complexity**: `INSTEAD OF` triggers are difficult to write, debug, and maintain, especially for complex, multi-stage logic.
    -   **Poor Performance**: Data would be copied multiple times (from `_data` to the `INSERT` statement, to the `INSERTED` pseudo-table, and likely into a temp table within the trigger).
    -   **Impractical Result Handling**: Returning detailed results from a trigger back to the calling `INSERT` statement is complex and cumbersome.

### Option 4: The Updatable View Function (Advanced)

This is a more sophisticated evolution of Option 2, addressing its main weakness (tight coupling to column names).

-   **Name**: `import.apply_temporal_merge`
-   **Feasibility**: High, but requires advanced understanding of PostgreSQL.
-   **Implementation**: A `VOLATILE` function that `RETURNS TABLE(...)` and accepts the *name* of an updatable view as an argument.
    1.  The `process_*` procedure creates a simple, updatable view over its `_data` table, aliasing its specific columns to a standard contract (e.g., `entity_pk_jsonb`, `conceptual_key`, `action`).
    2.  It calls `import.apply_temporal_merge(p_source_view_name => 'my_temp_view', ...)`.
    3.  The function uses dynamic SQL to query the view, perform the first `temporal_merge` call for `'insert'` actions.
    4.  Crucially, it then executes an `UPDATE my_temp_view SET entity_pk_jsonb = ... WHERE conceptual_key = ...` statement. Because the view is updatable, this transparently modifies the underlying `_data` table, propagating the new IDs.
    5.  It performs the second `temporal_merge` call for the remaining actions.
    6.  It returns a consolidated log of results.
-   **Pros**:
    -   **Superior Decoupling**: This is the biggest advantage. The function is completely decoupled from the schema of the `_data` tables. The view acts as an "Adapter," translating the specific schema to the standard interface the function expects.
    -   **Very Clean Call Site**: The `process_*` procedure's logic is reduced to `CREATE VIEW`, `SELECT FROM function()`, `DROP VIEW`.
    -   **Ergonomic API**: `RETURNS TABLE` is easy to work with.
-   **Cons**:
    -   **High "Magic" Factor**: This is the most significant drawback. The function modifies its input source (the underlying table of the view) as a side effect. This is a non-obvious and potentially surprising behavior for a `SELECT` function, violating the Principle of Least Surprise. The name `apply_...` itself contributes to this confusion, as discussed in the Naming Conventions section.
    -   **Increased Complexity**: This pattern is powerful but complex. Debugging requires understanding views, functions with side effects, and dynamic SQL.

**Conclusion**: All four options are feasible to varying degrees.
- The **Orchestrator Procedure** (Option 1) remains the most straightforward and recommended path. It provides a good balance of abstraction and clarity without introducing non-obvious side effects.
- The **Updatable View Function** (Option 4) is the most powerful and flexible solution from a software design perspective, offering superior decoupling. However, its "magic" side effects make it a pattern to be adopted with caution, ensuring the development team is comfortable with the advanced concepts involved.
