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

## 3. Critical Issue: Intra-Batch Dependencies

The most complex problem in the processing phase is handling dependencies between rows *within the same batch*.

**The Scenario:** A single batch for `process_legal_unit` contains two rows for the same new legal unit:
-   **Row 1**: The first historical record (`action=insert`). It needs to create a new `legal_unit.id`.
-   **Row 2**: A subsequent historical record (`action=replace`). It **depends on** the `legal_unit.id` from Row 1.

**The Question:** Who is responsible for resolving this dependency?

**The Answer:** The `process_*` procedure is responsible. The `temporal_merge` function and its planner are powerful but "dumb" tools; they are unaware of the logical dependencies between source rows and only know how to correctly merge a set of changes into a target table's timeline based on the explicit `mode` they are given.

## 4. How It's Addressed: Two-Stage Logic and Complete Feedback

The dependency problem is solved by a combination of two-stage logic within the `process_*` procedures and the "complete feedback" provided by the `temporal_merge` orchestrator.

For a detailed walkthrough of this process, see [Advanced Data Flow: Intra-Batch Dependencies and the Two-Stage Process](./temporal_merge_complex_flow_example.md).

The key principles are:
1.  **Two-Stage Processing**: The `process_*` procedure first isolates and processes all `insert` actions for new entities. This creates the necessary database records and generates their stable IDs.
2.  **ID Propagation**: The procedure then updates the job's `_data` table, back-filling the newly generated IDs into all other rows in the batch that refer to the same conceptual entities.
3.  **Complete Feedback**: The `temporal_merge` function provides a result status for *every* source row passed to it. This is crucial when the planner merges multiple source rows into a single database operation. The orchestrator unnests the merged source row IDs and reports `SUCCESS` for all of them, ensuring the calling `process_*` procedure knows that every row has been handled.

This pattern makes the dependency resolution explicit and robust.

## 5. The Role of `mode`: Explicitly Defining Intent

The `temporal_merge` function requires a `mode` parameter that makes the caller's intent explicit. This is critical for correctness.

-   **`upsert_patch` / `upsert_replace`**: Used for the first stage of processing. These modes will create new entities if they don't exist.
-   **`patch_only` / `replace_only`**: Used for the second stage. These modes will only modify existing entities and return `MISSING_TARGET` if an entity doesn't exist. This provides a safety guarantee, preventing accidental creation of duplicate entities.

This explicit API is what allows the two-stage processing logic to work safely and reliably.
