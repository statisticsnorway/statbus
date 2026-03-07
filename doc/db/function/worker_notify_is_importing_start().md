```sql
CREATE OR REPLACE PROCEDURE worker.notify_is_importing_start()
 LANGUAGE plpgsql
AS $procedure$
BEGIN
    -- Apply session-level PostgreSQL optimizations for import operations
    -- This ensures all subsequent queries in this transaction benefit from:
    -- - Increased work_mem (1GB) for large hash tables and sorts
    -- - Optimized join strategies (hash joins preferred over merge/nested loops)
    -- - Large hash_mem_multiplier (8x) for complex operations
    -- Settings automatically revert when transaction completes
    PERFORM admin.set_optimal_import_session_settings();
    
    -- Notify that importing has started
    PERFORM pg_notify('worker_status', json_build_object('type', 'is_importing', 'status', true)::text);
END;
$procedure$
```
