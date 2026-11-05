```sql
                                                                                                                                                                                                                           Table "worker.statistical_history_facet_delta_state"
       Column       |  Type   | Collation | Nullable | Default | Storage | Compression | Stats target |                                                                                                                                                                                            Description                                                                                                                                                                                            
--------------------+---------+-----------+----------+---------+---------+-------------+--------------+---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
 flushed_generation | bigint  |           | not null | 0       | plain   |             |              | Generation of the last cycle whose history staging completed and whose statistical_unit_flush_staging committed (set by that flush, in its transaction). Staged rows with generation <= flushed_generation are true and are added by the reduce; rows above it belong to a cycle whose flush never committed, and the next cycle replaces them (its units are still in statistical_unit_staging).
 rebuild_generation | bigint  |           |          |         | plain   |             |              | Generation of a rebuild cycle not yet added. Its reduce replaces public.statistical_history_facet_delta in one transaction, so readers keep the previous rows until the rebuilt ones commit. While set, every cycle rebuilds.
 rebuild_needed     | boolean |           | not null | false   | plain   |             |              | Set when statistical_unit_flush_staging ran in a task tree without a history step (a tree spawned before this design, or a direct call), so units moved without their deltas; the next cycle rebuilds.
Indexes:
    "statistical_history_facet_delta_state_single_row" UNIQUE, btree ((true))
Not-null constraints:
    "statistical_history_facet_delta_sta_flushed_generation_not_null" NOT NULL "flushed_generation"
    "statistical_history_facet_delta_state_rebuild_needed_not_null" NOT NULL "rebuild_needed"
Access method: heap

```

**Comment:** One row: which staged history delta rows count. A cycle's rows carry its generation (the derive_statistical_history_facet_delta task id); they count once the flush of that cycle has committed.
