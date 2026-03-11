```sql
                                                        Table "worker.pipeline_progress"
            Column            |           Type           | Collation | Nullable | Default | Storage  | Compression | Stats target | Description 
------------------------------+--------------------------+-----------+----------+---------+----------+-------------+--------------+-------------
 phase                        | worker.pipeline_phase    |           | not null |         | plain    |             |              | 
 step                         | text                     |           |          |         | extended |             |              | 
 total                        | integer                  |           | not null | 0       | plain    |             |              | 
 completed                    | integer                  |           | not null | 0       | plain    |             |              | 
 affected_establishment_count | integer                  |           |          |         | plain    |             |              | 
 affected_legal_unit_count    | integer                  |           |          |         | plain    |             |              | 
 affected_enterprise_count    | integer                  |           |          |         | plain    |             |              | 
 affected_power_group_count   | integer                  |           |          |         | plain    |             |              | 
 updated_at                   | timestamp with time zone |           | not null | now()   | plain    |             |              | 
Indexes:
    "pipeline_progress_pkey" PRIMARY KEY, btree (phase)
Not-null constraints:
    "pipeline_progress_phase_not_null" NOT NULL "phase"
    "pipeline_progress_total_not_null" NOT NULL "total"
    "pipeline_progress_completed_not_null" NOT NULL "completed"
    "pipeline_progress_updated_at_not_null" NOT NULL "updated_at"
Access method: heap

```
