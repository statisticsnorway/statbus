```sql
                        Unlogged table "worker.pipeline_progress"
            Column            |           Type           | Collation | Nullable | Default 
------------------------------+--------------------------+-----------+----------+---------
 phase                        | worker.pipeline_phase    |           | not null | 
 step                         | text                     |           |          | 
 total                        | integer                  |           | not null | 0
 completed                    | integer                  |           | not null | 0
 affected_establishment_count | integer                  |           |          | 
 affected_legal_unit_count    | integer                  |           |          | 
 affected_enterprise_count    | integer                  |           |          | 
 affected_power_group_count   | integer                  |           |          | 
 updated_at                   | timestamp with time zone |           | not null | now()
Indexes:
    "pipeline_progress_pkey" PRIMARY KEY, btree (phase)

```
