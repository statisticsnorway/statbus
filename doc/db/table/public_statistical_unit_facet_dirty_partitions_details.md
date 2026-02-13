```sql
                        Unlogged table "public.statistical_unit_facet_dirty_partitions"
    Column     |  Type   | Collation | Nullable | Default | Storage | Compression | Stats target | Description 
---------------+---------+-----------+----------+---------+---------+-------------+--------------+-------------
 partition_seq | integer |           | not null |         | plain   |             |              | 
Indexes:
    "statistical_unit_facet_dirty_partitions_pkey" PRIMARY KEY, btree (partition_seq)
Not-null constraints:
    "statistical_unit_facet_dirty_partitions_partition_seq_not_null" NOT NULL "partition_seq"
Access method: heap

```
