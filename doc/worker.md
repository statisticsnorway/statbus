# Worker System Architecture

This document describes the architecture and operation of the STATBUS background worker system. The worker is responsible for handling asynchronous tasks such as deriving statistical data, performing data cleanup, and processing imports.

For details on how the worker's status is communicated to the frontend for UI notifications, see [Worker Notifications](./worker-notifications.md).
For the derive pipeline (how statistical tables are computed), see [Derive Pipeline](./derive-pipeline.md).
For structured concurrency (parent/child task model), see [Structured Concurrency](./worker-structured-concurrency.md).

## 1. Core Architecture

The system is composed of two main parts: a PostgreSQL-based task queue and a Crystal-based worker process.

![Worker Architecture Diagram](../.docs/diagrams/worker-architecture.png)

1.  **PostgreSQL Task Queue**:
    *   **`worker.tasks`**: The central table where tasks are stored. Each row represents a unit of work with a state (`pending`, `processing`, `completed`, `failed`), a command, and a JSONB payload.
    *   **`worker.command_registry`**: A table that maps a command name (e.g., `derive_statistical_unit`) to a specific PostgreSQL handler procedure. It also defines which queue a command belongs to and optional `before` and `after` hook procedures.
    *   **`worker.enqueue_*` Functions**: A set of SQL functions (e.g., `worker.enqueue_derive_statistical_unit()`) used to create tasks. These functions handle deduplication and merging of similar pending tasks.
    *   **`NOTIFY/LISTEN`**: The system uses PostgreSQL's `NOTIFY` mechanism to signal the Crystal worker that new tasks are available, reducing polling and latency.

2.  **Crystal Worker Process (`cli/src/worker.cr`)**:
    *   This is a long-running process that listens for notifications on the `worker_tasks` channel.
    *   It acts as a lightweight **dispatcher**. Its primary role is to call the `worker.process_tasks()` PostgreSQL procedure when notified.
    *   It manages separate processing loops for different queues (e.g., `analytics`, `maintenance`) to handle task prioritization and concurrency.
    *   It ensures that only one instance of the worker is running at a time by using a PostgreSQL advisory lock (`pg_try_advisory_lock`). On startup, it attempts to acquire a session-level lock using a consistent, hashed key. If the lock is already held, it assumes another worker is active and exits immediately. The lock is automatically released if the session ends, or explicitly released on graceful shutdown.

## 2. Task Execution

Task execution is handled entirely within PostgreSQL by the `worker.process_tasks` procedure.

### Execution Flow

1.  **Dispatch**: The Crystal worker calls `worker.process_tasks(p_queue => '...')`.
2.  **Task Claiming**: The procedure queries `worker.tasks` for a pending task, acquiring a row-level lock using `FOR UPDATE SKIP LOCKED` to prevent race conditions with other worker instances (though the advisory lock should already prevent this).
3.  **Execution**: The task's state is set to `processing`. The procedure then calls the appropriate handler procedure (defined in `worker.command_registry`) for the task's command.
4.  **Result**: Upon completion, the task's state is updated to `completed` or `failed`, and the duration and any errors are recorded.
5.  **Synchronous Nature**: The `worker.process_tasks` call is synchronous and blocking. The Crystal worker waits for it to complete and then queries the `worker.tasks` table to find out what was processed and log the results.

## 3. Resilience and Recovery

The worker is designed to be self-healing and recover from unexpected shutdowns or task failures.

### Abandoned Task Recovery

The worker is designed to recover from unexpected shutdowns, such as a process crash that leaves a hanging database session holding locks.

When the Crystal worker starts, it calls `worker.reset_abandoned_processing_tasks()`. This function performs the following cleanup:
1.  It finds all tasks that were left in the `processing` state.
2.  When a task begins processing, its row in `worker.tasks` is updated with the current backend's Process ID (PID) in the `worker_pid` column.
3.  The cleanup function checks `pg_stat_activity` to see if the stored `worker_pid` for an abandoned task is still active.
4.  If the process is still running, it is terminated using `pg_terminate_backend()` to release any locks it may be holding.
5.  Finally, the task's state is reset to `pending`, allowing it to be safely re-processed by the new worker instance.

## 4. Development and Testing

### Adding a New Command

1.  **Create a Handler Procedure**: Write a PostgreSQL procedure that accepts a single `JSONB` payload argument (e.g., `CREATE PROCEDURE my_schema.my_handler(payload JSONB)`).
2.  **Register the Command**: Add a new row to `worker.command_registry`, linking your command name to the new handler procedure and assigning it to a queue.
3.  **Create an Enqueue Function**: Create a `worker.enqueue_my_command(...)` function. This function should construct the JSONB payload and insert it into `worker.tasks`. It is best practice to implement deduplication logic here using an `ON CONFLICT` clause to merge new data into an existing pending task.

### Testing

The worker system is designed to be testable within a standard `pg_regress` test.

```sql
-- Example for a pg_regress test
BEGIN;

-- 1. Set up your test data. This action will likely create one or more
--    'pending' tasks in the worker.tasks table.
INSERT INTO public.establishment (...) VALUES (...);

-- 2. Manually call the worker procedure. The call is synchronous.
CALL worker.process_tasks(p_queue => 'analytics');

-- 3. You can immediately verify their results.
SELECT * FROM public.statistical_unit WHERE ...;

-- The transaction is rolled back, cleaning up both the test data and any
-- changes made by the worker tasks.
ROLLBACK;
```
