```sql
                         Unlogged table "public.statistical_unit_facet_dirty_hash_slots"
     Column      |  Type   | Collation | Nullable | Default | Storage | Compression | Stats target | Description 
-----------------+---------+-----------+----------+---------+---------+-------------+--------------+-------------
 dirty_hash_slot | integer |           | not null |         | plain   |             |              | 
Indexes:
    "statistical_unit_facet_dirty_hash_slots_pkey" PRIMARY KEY, btree (dirty_hash_slot)
Not-null constraints:
    "statistical_unit_facet_dirty_hash_slots_dirty_hash_slot_not_nul" NOT NULL "dirty_hash_slot"
Access method: heap

```
